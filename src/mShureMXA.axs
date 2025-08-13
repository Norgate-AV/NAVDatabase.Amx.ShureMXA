MODULE_NAME='mShureMXA'     (
                                dev vdvObject,
                                dev dvPort
                            )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
#DEFINE USING_NAV_STRING_GATHER_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.ArrayUtils.axi'
#include 'NAVFoundation.StringUtils.axi'
#include 'NAVFoundation.ErrorLogUtils.axi'
#include 'NAVFoundation.TimelineUtils.axi'
#include 'LibShureMXA.axi'

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

constant long TL_SOCKET_CHECK   = 1
constant long TL_HEARTBEAT      = 2

constant long TL_SOCKET_CHECK_INTERVAL[] = { 3000 }
constant long TL_HEARTBEAT_INTERVAL[]    = { 20000 }


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

struct _Object {
    char mute
    integer level
}

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _Object object

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

define_function SendString(char payload[]) {
    payload = "payload, NAV_CR, NAV_LF"

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO,
                                            dvPort,
                                            payload))

    send_string dvPort, "payload"
    wait 1 module.CommandBusy = false
}


define_function MaintainSocketConnection() {
    if (module.Device.SocketConnection.IsConnected) {
        return
    }

    NAVClientSocketOpen(dvPort.PORT,
                        module.Device.SocketConnection.Address,
                        module.Device.SocketConnection.Port,
                        IP_TCP)
}


#IF_DEFINED USING_NAV_STRING_GATHER_CALLBACK
define_function NAVStringGatherCallback(_NAVStringGatherResult args) {
    stack_var char data[NAV_MAX_BUFFER]
    stack_var char delimiter[NAV_MAX_CHARS]
    stack_var char properties[10][255]

    data = args.Data
    delimiter = args.Delimiter

    if (NAVContains(data, 'BEAM_X') || NAVContains(data, 'BEAM_Y') || NAVContains(data, 'BEAM_Z')) {
        // Ignore all the noise
        return
    }

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM,
                                            dvPort,
                                            data))

    data = NAVStringBetween(data, '< ', ' >')

    if (!NAVStartsWith(data, 'REP')) {
        return
    }

    remove_string(data, 'REP ', 1)

    select {
        active(NAVContains(data, COMMAND_SERIAL_NUM)): {
            // Heartbeat response

            if (module.Device.IsInitialized) {
                return
            }

            Init()
        }
        active(NAVContains(data, COMMAND_DEVICE_AUDIO_MUTE)): {
            object.mute = NAVEndsWith(data, 'ON')
            UpdateFeedback()
        }
        active(NAVContains(data, COMMAND_AUDIO_GAIN_HI_RES)): {
            stack_var integer index
            stack_var integer level

            index = atoi(NAVStripRight(remove_string(data, ' ', 1), 1))

            if (index != INDEX_AUTOMIXER) {
                // Not interested in anything other than the automixer
                return
            }

            level = atoi(NAVStripLeft(data, NAVLastIndexOf(data, ' ') + 1))

            if (object.level != level) {
                object.level = level
                send_level vdvObject, VOL_LVL, object.level * (MAX_LEVEL - MIN_LEVEL) / 255
            }

            module.Device.IsInitialized = true
        }
    }
}
#END_IF


define_function Init() {
    SendString(BuildMuteQuery())
    SendString(BuildAudioGainQuery(INDEX_AUTOMIXER))
}


define_function CommunicationTimeOut(integer timeout) {
    cancel_wait 'TimeOut'

    module.Device.IsCommunicating = true
    UpdateFeedback()

    wait (timeout * 10) 'TimeOut' {
        module.Device.IsCommunicating = false
        UpdateFeedback()
    }
}


define_function Reset() {
    module.Device.SocketConnection.IsConnected = false
    module.Device.IsCommunicating = false
    module.Device.IsInitialized = false
    UpdateFeedback()

    NAVTimelineStop(TL_HEARTBEAT)
}


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    switch (event.Name) {
        case NAV_MODULE_PROPERTY_EVENT_IP_ADDRESS: {
            module.Device.SocketConnection.Address = NAVTrimString(event.Args[1])
            module.Device.SocketConnection.Port = IP_PORT
            NAVTimelineStart(TL_SOCKET_CHECK,
                            TL_SOCKET_CHECK_INTERVAL,
                            TIMELINE_ABSOLUTE,
                            TIMELINE_REPEAT)
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
define_function NAVModulePassthruEventCallback(_NAVModulePassthruEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    SendString(event.Payload)
}
#END_IF


define_function SendHeartbeat() {
    SendString(BuildHeartbeatCommand())
}


define_function UpdateFeedback() {
    [vdvObject, VOL_MUTE_FB] = (object.mute)
    [vdvObject, NAV_IP_CONNECTED]	= (module.Device.SocketConnection.IsConnected)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
    [vdvObject, DATA_INITIALIZED] = (module.Device.IsInitialized)
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort, module.RxBuffer.Data
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        if (data.device.number == 0) {
            module.Device.SocketConnection.IsConnected = true
            UpdateFeedback()
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mShureMXA => Socket Online'")
        }

        SendHeartbeat()

        NAVTimelineStart(TL_HEARTBEAT,
                        TL_HEARTBEAT_INTERVAL,
                        TIMELINE_ABSOLUTE,
                        TIMELINE_REPEAT)
    }
    offline: {
        if (data.device.number == 0) {
            NAVClientSocketClose(data.device.port)
            Reset()
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mShureMXA => Socket Offline'")
        }
    }
    onerror: {
        if (data.device.number == 0) {
            Reset()
            NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                        "'mShureMXA => Socket Error: ', NAVGetSocketError(type_cast(data.number))")
        }

    }
    string: {
        CommunicationTimeOut(30)

        select {
            active (true): {
                NAVStringGather(module.RxBuffer, DELIMITER)
            }
        }
    }
}


data_event[vdvObject] {
    online: {
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_DESCRIPTION,Microphone Array'")
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_MANUFACTURER_URL,shure.com'")
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_MANUFACTURER_NAME,Shure'")
    }
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            case NAV_MODULE_EVENT_MUTE: {
                switch (message.Parameter[1]) {
                    case 'ON': { SendString(BuildMuteCommand(true)) }
                    case 'OFF': { SendString(BuildMuteCommand(false)) }
                }
            }
            case NAV_MODULE_EVENT_VOLUME: {
                switch (message.Parameter[1]) {
                    case 'ABS': {
                        if ((atoi(message.Parameter[2]) >= MIN_LEVEL) && (atoi(message.Parameter[2]) <= MAX_LEVEL)) {
                            SendString(BuildAudioGainCommand(INDEX_AUTOMIXER, atoi(message.Parameter[2])))
                        }
                    }
                    default: {
                        stack_var sinteger level
                        stack_var sinteger min
                        stack_var sinteger max

                        // Remove the decimal point
                        min = MIN_LEVEL / 10
                        max = MAX_LEVEL / 10

                        level = NAVScaleValue(atoi(message.Parameter[1]),
                                                255,
                                                (max - min),
                                                min)

                        if ((level >= min) && (level <= max)) {
                            SendString(BuildAudioGainCommand(INDEX_AUTOMIXER, type_cast(level * 10)))
                        }
                    }
                }
            }
        }
    }
}


timeline_event[TL_SOCKET_CHECK] { MaintainSocketConnection() }


timeline_event[TL_HEARTBEAT] {
    SendHeartbeat()
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
