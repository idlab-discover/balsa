// Treelite 4.6.1 public C ABI; linked to the benchmark environment's wheel.
#ifdef PROFILE_CLIENT
extern "C" void profile_begin();
extern "C" void profile_end();
#else
static void profile_begin() {}
static void profile_end() {}
#endif
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>

extern "C" {
int TreeliteDeserializeModelFromBytes(const char*, std::size_t, void**);
int TreeliteSerializeModelToBytes(void*, const char**, std::size_t*);
int TreeliteFreeModel(void*);
const char* TreeliteGetLastError();
}
void check(int result) {
  if (result != 0) throw std::runtime_error(TreeliteGetLastError());
}
struct Model {
  void* handle = nullptr;
  explicit Model(const std::string& bytes) {
    check(TreeliteDeserializeModelFromBytes(bytes.data(), bytes.size(), &handle));
  }
  ~Model() { if (handle) TreeliteFreeModel(handle); }
  Model(const Model&) = delete;
  Model& operator=(const Model&) = delete;
};
void keep(const void* value) { asm volatile("" : : "g"(value) : "memory"); }
std::string encode(Model& model) {
  const char* bytes = nullptr;
  std::size_t size = 0;
  check(TreeliteSerializeModelToBytes(model.handle, &bytes, &size));
  // C API output belongs to Treelite TLS. Return independent owned bytes,
  // matching Balsa and Treelite's Python serialize_bytes contract.
  return std::string(bytes, size);
}
__attribute__((noinline)) std::uint64_t decode_once(const std::string& bytes) {
  Model model(bytes);
  keep(model.handle);
  return 1;
}
__attribute__((noinline)) std::uint64_t encode_once(Model& model) {
  auto bytes = encode(model);
  keep(bytes.data());
  return bytes.size();
}
__attribute__((noinline)) std::uint64_t roundtrip_once(const std::string& bytes) {
  Model model(bytes);
  auto output = encode(model);
  keep(output.data());
  return output.size();
}
int main(int argc, char** argv) {
  try {
    if (argc != 4) throw std::runtime_error("CHECKPOINT OPERATION LOOPS required");
    const std::string operation = argv[2];
    const auto loops = std::stoull(argv[3]);
    if (!loops) throw std::runtime_error("Positive loops required");
    std::ifstream file(argv[1], std::ios::binary);
    if (!file) throw std::runtime_error("Cannot open checkpoint");
    const std::string bytes((std::istreambuf_iterator<char>(file)), {});
    Model model(bytes);
    if (encode(model) != bytes) throw std::runtime_error("Byte parity failed before timing");
    auto batch = [&](std::uint64_t count) {
      std::uint64_t sum = 0;
      if (operation == "decode") {
        for (std::uint64_t i=0; i<count; ++i) sum += decode_once(bytes);
      } else if (operation == "encode") {
        for (std::uint64_t i=0; i<count; ++i) sum += encode_once(model);
      } else if (operation == "roundtrip") {
        for (std::uint64_t i=0; i<count; ++i) sum += roundtrip_once(bytes);
      } else throw std::runtime_error("Unknown operation");
      return sum;
    };
    keep(reinterpret_cast<const void*>(batch(8)));
    asm volatile("" ::: "memory");
    profile_begin();
    auto start = std::chrono::steady_clock::now();
    auto sum = batch(loops);
    asm volatile("" ::: "memory");
    double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    profile_end();
    std::cout << std::setprecision(17) << elapsed << ' ' << sum << '\n';
  } catch (const std::exception& e) {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
