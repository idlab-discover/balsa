// Treelite 4.6.1 file APIs. One operation per process, normal upstream checks.
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
extern "C" {
int TreeliteDeserializeModelFromFile(const char*, void**);
int TreeliteSerializeModelToFile(void*, const char*);
int TreeliteFreeModel(void*);
const char* TreeliteGetLastError();
}
void check(int code) {
  if (code) throw std::runtime_error(TreeliteGetLastError());
}
struct Model {
  void* handle = nullptr;
  ~Model() { if (handle) TreeliteFreeModel(handle); }
};
int main(int argc, char** argv) {
  try {
    if (argc != 4) throw std::runtime_error("FILE OP OUTPUT required");
    std::string op = argv[2];
    if (op != "load" && op != "save" && op != "roundtrip")
      throw std::runtime_error("Unknown operation");
    Model model;
    if (op == "save") check(TreeliteDeserializeModelFromFile(argv[1], &model.handle));
    auto start = std::chrono::steady_clock::now();
    if (op != "save") check(TreeliteDeserializeModelFromFile(argv[1], &model.handle));
    if (op != "load") check(TreeliteSerializeModelToFile(model.handle, argv[3]));
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::cout << ns << '\n';
  } catch (const std::exception& e) {
    std::cerr << e.what() << '\n';
    return 1;
  }
}
