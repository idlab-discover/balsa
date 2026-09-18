// Linux worker peak RSS without a GNU time dependency or Python parent RSS.
#include <cerrno>
#include <cstdio>
#include <iostream>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char** argv) {
  if (argc < 2) return 2;
  pid_t pid = fork();
  if (pid < 0) { perror("fork"); return 1; }
  if (pid == 0) {
    execv(argv[1], argv + 1);
    perror("execv");
    _exit(127);
  }
  int status = 0;
  rusage usage{};
  while (wait4(pid, &status, 0, &usage) < 0) {
    if (errno != EINTR) { perror("wait4"); return 1; }
  }
  if (!WIFEXITED(status)) return 1;
  if (WEXITSTATUS(status)) return WEXITSTATUS(status);
  std::cout << usage.ru_maxrss << '\n';
}
