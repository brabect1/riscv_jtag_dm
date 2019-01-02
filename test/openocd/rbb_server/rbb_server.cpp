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
  sockfd(0),
  clientfd(0),
  backend(NULL)
{
    this->backend = backend;
}

int rbb_server::finished() {
    return (sockfd == 0 && clientfd == 0);
}

void rbb_server::fininsh() {
    if (sockfd != 0) {
        if (clientfd != 0) {
            close(clientfd);
            clientfd = 0;
        }

        close(sockfd);
        sockfd = 0;
    }
}

//TODO: may consider flockfile() for thread safety of stderr output operations
void rbb_server::listen(uint16_t port) {

    // create a new socket
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        fprintf(stderr, "ERROR opening socket (%d): %s\n", errno, strerror(errno));
        sockfd = 0;
        abort();
    }

//    // make the socket non-blocking
//    fcntl(sockfd, F_SETFL, O_NONBLOCK);

    // make the socket reuse the address (e.g. even if blocked by a crashed process)
    int reuseaddr = 1;
    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr, sizeof(int)) < 0) {
        fprintf(stderr, "ERROR setsockopt(SO_REUSEADDR) failed (%d): %s\n", errno, strerr(errno));
        close(sockfd);
        sockfd = 0;
        abort();
    }

    // bind the socket to a port
    struct sockaddr_in sockaddr;
    sockaddr.sin_family = AF_INET;
    sockaddr.sin_addr.s_addr = INADDR_ANY;
    sockaddr.sin_port = htons(port);
    if (bind(sockfd, (struct sockaddr*)&sockaddr, sizeof(sockaddr)) < 0) {
        fprintf(stderr, "ERROR binding socket to port %d (%d): %s\n", port, errno, strerr(errno));
        close(sockfd);
        sockfd = 0;
        abort();
    }

    // listen to connections
    if (::listen(sockfd,1) < 0) {
        fprintf(stderr, "ERROR listening on a bound socket (%d): %s\n", errno, strerr(errno));
        close(sockfd);
        sockfd = 0;
        abort();
    }
    
    fprintf(stderr, "RBB server listening on port %d\n", port);
}

void rbb_server::accept() {
    struct sockaddr_in clientaddr;
    if (clientfd == 0 && sockfd != 0) {
        clientfd = ::accept(sockfd, (struct sockaddr*)&clientaddr, sizeof(clientaddr));
        if (clientfd < 0) {
            fprintf(stderr, "ERROR accepting client connection (%d): %s\n", errno, strerr(errno));
            close(sockfd);
            sockfd = 0;
            clientfd = 0;
            abort();
        }
    }
}

void rbb_server::respond() {
    char c;
    char respond;
    if (clientfd != 0) {
        ssize_t n = read(clientfd,&c,sizeof(c));
        if (n < 0) {
            fprintf(stderr, "ERROR receiving command (%d): %s\n", errno, strerr(errno));
            return;
        }

        respond = 0;
        switch (c) {
            case 'R': respond='1'; break;
            default:
                fprintf(stderr,"WARN unknown command '%c'\n", c);
        }

        if (respond != 0) {
            ssize_t n = write(clientfd, &respond, sizeof(respond));
            if (n < 0) {
                fprintf(stderr, "ERROR sending response '%c' (%d): %s\n", response, errno, strerr(errno));
            }
        }
    }
}

