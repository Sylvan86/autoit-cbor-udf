## Introduction

[CBOR](https://cbor.io/) is a binary format that can represent arbitrarily nested data.
The principle is basically the same as with JSON.
There you can take your variables directly from the program and convert them to this format.
This way you can store your data outside the program or exchange it with other programs, which is even easier since almost all programming languages understand the JSON standard.

CBOR is quite similar, but the difference is that CBOR is not a text-based format, but a binary format.
This of course makes it impossible for a human to read it directly but on the other hand the results are usually smaller than in JSON.

## How to use?
Now how to work with it? - Here is an example:
```AutoIt
#include "CBOR.au3"

; create nested AutoIt-structure
Global $aArray = [1, 2.0, 3.3]
Global $vValue[] ; empty map
    $vValue["test"] = $aArray
    $vValue[123] = "string"

; serialize AutoIt-variables into binary CBOR-format:
$bCBOR = _cbor_encode($vValue)
ConsoleWrite(StringFormat("% 20s: % 8d bytes\n", "serialized size", BinaryLen($bCBOR)))

; reconvert from cbor-binary into AutoIt-variable:
$vAutoIt = _cbor_decode($bCBOR)

; check if structure is o.k:
ConsoleWrite($vAutoIt.test[2] & @CRLF)
```

In this case our AutoIt data structure occupies 29 bytes of space at the end.

Since the comparison to JSON is obvious - here is another example (the [JSON UDF](https://github.com/Sylvan86/autoit-json-udf) is also needed) to see how both interact:

```AutoIt
#include "CBOR.au3"
#include "JSON.au3"

; Data in JSON-format
Global $sString = '[{"id":"4434156","url":"https://legacy.sky.com/v2/schedules/4434156","title":"468_CORE_1_R.4 Schedule","time_zone":"London","start_at":"2017/08/10 19:00:00 +0100","end_at":null,"notify_user":false,"delete_at_end":false,"executions":[],"recurring_days":[],"actions":[{"type":"run","offset":0}],"next_action_name":"run","next_action_time":"2017/08/10 14:00:00 -0400","user":{"id":"9604","url":"https://legacy.sky.com/v2/users/9604","login_name":"robin@ltree.com","first_name":"Robin","last_name":"John","email":"robin@ltree.com","role":"admin","deleted":false},"region":"EMEA","can_edit":true,"vm_ids":null,"configuration_id":"19019196","configuration_url":"https://legacy.sky.com/v2/configurations/19019196","configuration_name":"468_CORE_1_R.4"},{"id":"4444568","url":"https://legacy.sky.com/v2/schedules/4444568","title":"468_CORE_1_R.4 Schedule","time_zone":"London","start_at":"2017/08/11 12:00:00 +0100","end_at":null,"notify_user":false,"delete_at_end":false,"executions":[],"recurring_days":[],"actions":[{"type":"suspend","offset":0}],"next_action_name":"suspend","next_action_time":"2017/08/11 07:00:00 -0400","user":{"id":"9604","url":"https://legacy.sky.com/v2/users/9604","login_name":"robin@ltree.com","first_name":"Robin","last_name":"John","email":"robin@ltree.com","role":"admin","deleted":false},"region":"EMEA","can_edit":true,"vm_ids":null,"configuration_id":"19019196","configuration_url":"https://legacy.sky.com/v2/configurations/19019196","configuration_name":"468_CORE_1_R.4"}]'
ConsoleWrite(StringFormat("% 20s: % 8d bytes\n", "size of json-string", BinaryLen(StringToBinary($sString, 4))))

; convert to CBOR-binary:
Global $bCBOR = _JsonToCbor($sString)
ConsoleWrite(StringFormat("% 20s: % 8d bytes\n", "size of cbor-binary", BinaryLen($bCBOR)))

; reconvert to json to prove cbor converts correct:
Global $sRecovered = _CborToJson($bCBOR)
ConsoleWrite($sRecovered & @CRLF)

Func _JsonToCbor($sJSONString)
    Local $vData = _JSON_Parse($sString)
    Return _cbor_encode($vData)
EndFunc

Func _CborToJson($bCBOR)
    Local $vDecoded = _cbor_decode($bCBOR)
    Return _JSON_Generate($vDecoded)
EndFunc
```