cmake_minimum_required(VERSION 3.17)
project(archive_filter_fork_stub C)

# Built through CMake, rather than a bare clang call in build-variant.sh, so it
# picks up exactly the sysroot, architecture and deployment target the rest of
# the variant was built with.
add_library(archive_filter_fork_stub STATIC filter_fork_stub.c)
install(TARGETS archive_filter_fork_stub ARCHIVE DESTINATION lib)
