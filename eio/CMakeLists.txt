
INCLUDE(CheckIncludeFiles)

CHECK_INCLUDE_FILES(inttypes.h HAVE_INTTYPES_H)

SET(FC_CHAR_PTR "(P,L) char *P")

CONFIGURE_FILE(config.h.cmake config.h)

INCLUDE_DIRECTORIES("${PROJECT_BINARY_DIR}")
INCLUDE_DIRECTORIES("${PROJECT_BINARY_DIR}/eio/src")

ADD_SUBDIRECTORY(src)

