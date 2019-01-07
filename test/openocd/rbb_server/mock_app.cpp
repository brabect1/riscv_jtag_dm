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


#include <iostream>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>

#include "rbb_server.h"

using namespace std;

/**
* Implements a simple RBB backend that only prints messages corresponding
* to actions requested from the assigned RBB frontend server.
*/
class mock_backend: public rbb_backend {

    private:
        rbb_server* srv;

    public:

        mock_backend() :
            srv(NULL)
        {
        }

        virtual rbb_server* getServer() {
            return srv;
        }

        virtual int setServer( rbb_server* server ) {
            if (srv == NULL) {
                srv = server;
                return 0;
            } else {
                return 1;
            }
        }

        virtual void init() {
            cout << "mock_backend: JTAG initialized." << endl;
        }

        virtual void reset() {
            cout << "mock_backend: JTAG reset." << endl;
        }

        virtual void quit() {
            cout << "mock_backend: QUIT." << endl;
            if (srv) srv->finish();
        }

        virtual void blink(int on) {
            if (on) {
                cout << "mock_backend: **BLINK ON**" << endl;
            } else {
                cout << "mock_backend: **BLINK OFF**" << endl;
            }
        }

        virtual void setInputs(int tck, int tms, int tdi) {
//            cout << "mock_backend: Setting TCK=" << tck << ", TMS=" << tms << ", TDI=" << tdi << endl;
        }

        virtual int getTdo() {
            cout << "mock_backend: Getting TDO(=1)." << endl;
            return 1;
        }
};


int main(int argc, char** argv) {
    // Port numbers are 16 bit unsigned integers. 
    uint16_t rbb_port = 9823;
    rbb_server* rbb;
    mock_backend* backend;

    cout << "server: Starting ..." << endl;

    backend = new mock_backend();
    rbb = new rbb_server(NULL);

    rbb->listen( rbb_port );
    rbb->accept();
    while (!rbb->finished()) {
        rbb->respond();
    }

    cout << "server: Finished." << endl;

    if (rbb) delete rbb;
    if (backend) delete backend;
    return 0;
}
