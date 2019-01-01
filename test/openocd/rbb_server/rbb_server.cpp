/*
Copyright 2019 Tomas Brabec

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstdlib>

#include "rbb_server.h"


rbb_server::rbb_server(rbb_backend* backend):
  socket_fd(0),
  client_fd(0),
  backend(NULL)
{
    this->backend = backend;
}

// Most of the code here comes from remote_bitbang.cc in https://github.com/freechipsproject/rocket-chip/tree/master/src/main/resources/csrc
rbb_server::listen(uint16_t port) {
    ... //TODO
}

void rbb_server::accept() {
    ... //TODO
}

void rbb_server::respond() {
    ... //TODO
}

