PROGRAM_NAME='LibShureMXA'

(***********************************************************)
#include 'NAVFoundation.Core.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/


#IF_NOT_DEFINED __LIB_SHUREMXA__
#DEFINE __LIB_SHUREMXA__ 'LibShureMXA'


DEFINE_CONSTANT

constant integer IP_PORT = 2202

constant char DELIMITER[] = '>'

constant integer COMMAND_TYPE_GET = 1
constant integer COMMAND_TYPE_SET = 2
constant integer COMMAND_TYPE_REP = 3

constant char COMMAND_TYPE[][NAV_MAX_CHARS]     =   {
                                                        'GET',
                                                        'SET',
                                                        'REP'
                                                    }


define_function char[NAV_MAX_BUFFER] BuildProtocol(integer type, char cmd[], char value[]) {
    stack_var char payload[NAV_MAX_BUFFER]

    payload = "COMMAND_TYPE[type], ' ', cmd"

    if (type != COMMAND_TYPE_GET) {
        payload = "payload, ' ', value"
    }

    return NAVStringSurround(payload, '< ', ' >')
}


define_function char[NAV_MAX_BUFFER] BuildMuteCommand(integer state) {
    return BuildProtocol(COMMAND_TYPE_SET, 'DEVICE_AUDIO_MUTE', upper_string(NAVBooleanToOnOffString(type_cast(state))))
}


#END_IF // __LIB_SHUREMXA__
