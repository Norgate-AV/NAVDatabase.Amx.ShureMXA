MODULE_NAME='mShureMXAFaderUIArray'	(
                                            dev dvTP[],
                                            dev vdvObject
                                        )

(***********************************************************)
#include 'NAVFoundation.SnapiHelpers.axi'
#include 'NAVFoundation.Math.axi'
#include 'NAVFoundation.UIUtils.axi'

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

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant integer ADDRESS_LEVEL_PERCENTAGE	= 1
constant integer ADDRESS_LABEL	= 2

constant integer LOCK_TOGGLE	= 301
constant integer LOCK_ON	= 302
constant integer LOCK_OFF	= 303
constant integer LEVEL_TOUCH	= 304


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile char locked = false

volatile char levelTouched = false

volatile sinteger currentLevel

volatile char label[NAV_MAX_CHARS] = ''


(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)

define_function Update(dev device[], sinteger level, char label[]) {
    if (levelTouched) {
        return
    }

    currentLevel = level

    NAVSendLevelArray(device, VOL_LVL, type_cast(level))

    // Log
    {
        stack_var integer x

        for (x = 1; x <= length_array(device); x++) {
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'Level Update To [', NAVDeviceToString(device[x]), ']: ', itoa(level)")
        }
    }

    NAVTextArray(device, ADDRESS_LEVEL_PERCENTAGE, '0', "itoa(NAVScaleValue(type_cast(level), 255, 100, 0)), '%'")

    NAVTextArray(dvTP, ADDRESS_LABEL, '0', label)
}


define_function LevelEventHandler(dev device[], tlevel level) {
    if (!levelTouched || locked) {
        return
    }

    NAVCommand(vdvObject, "'VOLUME-', itoa(level.value)")
    NAVTextArray(device, ADDRESS_LEVEL_PERCENTAGE, '0', "itoa(NAVScaleValue(type_cast(level.value), 255, 100, 0)), '%'")
}


define_function UpdateFeedback() {
    [dvTP, VOL_MUTE]	= ([vdvObject, VOL_MUTE_FB])
    [dvTP, LOCK_TOGGLE]	= (locked)
    [dvTP, LOCK_ON]	= (locked)
    [dvTP, LOCK_OFF]	= (!locked)
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {

}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

level_event[vdvObject, VOL_LVL] {
    Update(dvTP, level.value, label)
}


button_event[dvTP, 0] {
    push: {
        switch (button.input.channel) {
            case VOL_UP:
            case VOL_DN: {
                if (!locked) {
                    to[vdvObject, button.input.channel]
                }
            }
            case VOL_MUTE: {
                to[vdvObject, button.input.channel]
            }
            case LOCK_TOGGLE: {
                locked = !locked
                UpdateFeedback()
            }
            case LOCK_ON: {
                locked = true
                UpdateFeedback()
            }
            case LOCK_OFF: {
                locked = false
                UpdateFeedback()
            }
            case LEVEL_TOUCH: {
                levelTouched = true
            }
        }
    }
    release: {
        switch (button.input.channel) {
            case LEVEL_TOUCH: {
                levelTouched = false
            }
        }
    }
}


level_event[dvTP, VOL_LVL] {
    LevelEventHandler(dvTP, level)
}


data_event[dvTP] {
    online: {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'Device [', NAVDeviceToString(data.device), ']: Online'")

        Update(dvTP, currentLevel, label)
    }
    offline: {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'Device [', NAVDeviceToString(data.device), ']: Offline'")
    }
}


data_event[vdvObject] {
    online: {
        NAVCommand(data.device, "'?LABEL'")
    }
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            case 'PROPERTY': {
                switch (message.Parameter[1]) {
                    case 'LABEL': {
                        label = message.Parameter[2]
                        Update(dvTP, currentLevel, label)
                    }
                }
            }
        }
    }
    string: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            case 'VOLUME': {
                switch (message.Parameter[1]) {
                    case 'ABS': {
                        stack_var char level[4]

                        level = NAVStripRight(message.Parameter[2], 1)

                        if (!length_array(level)) {
                            level = '0'
                        }

                        NAVTextArray(dvTP, 11, '0', "level, 'dB'")
                    }
                }
            }
        }
    }
}


channel_event[vdvObject, VOL_MUTE_FB] {
    on: {
        UpdateFeedback()
    }
    off: {
        UpdateFeedback()
    }
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
