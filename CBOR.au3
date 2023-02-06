#include-once

;  Oriented on RFC 8949, but does not claim to be fully implemented.
;  https://www.rfc-editor.org/rfc/rfc8949.html

; not implemented yet:
; - tags (to mark date/time strings etc.)
; - bytewise lexicographic order of the map-keys
; - UINT64, bigfloats, bignums etc. due to the lack of corresponding autoit datatypes
; - indefinite length for arrays, maps, byte strings and text strings
; - "undefined" - is mapped to/from "Default"-keyword


Func _cbor_decode(ByRef $dInput, $iCurPos = 1)

	Local $dInitByte = BinaryMid($dInput, $iCurPos, 1)
	Local $iMajorType = Int(Bitshift($dInitByte, 5)) ; only 0-7 possible - so no extra range check
	Local $dNextPos = $iCurPos + 1

	; read out the additional info:
	Local $iAddInfo = Int(BitAND($dInitByte, 31))
	Local $iAddInfoLen = 1
	Local $bIndefinite = False
	Switch $iAddInfo
		Case 0 To 23
			;  $iAddInfo = $iAddInfo
		Case 24 To 27 ; following 1,2,4,8 Bytes
			$iAddInfoLen = 2^($iAddInfo-24)
			$iAddInfo = BinaryMid($dInput, $dNextPos, $iAddInfoLen)
			$dNextPos += $iAddInfoLen
		Case 28 To 30
			Return SetError(2, $iAddInfo, Null) ; exception: no valid value for additional info - not defined in bcor standard yet - only reserved for later
		Case 31 ; indefinite-length array or map (currently not supported)
			$bIndefinite = True
			;  If ($dInitByte < 2) Or ($dInitByte = 6) Then Return SetError(3, $dInitByte, Null) ; exception: invalid combination of major type and additional info
			Return SetError(3, $iAddInfo, Null)
	EndSwitch ; no case else because all possible values are handled (5 bits = 0..31)


	; handle the different element types
	Switch $iMajorType
		Case 0 ; unsigned int          - no content
			If $iAddInfoLen > 1 Then $iAddInfo = _cbor_swapEndianess($iAddInfo)
			Return SetExtended($dNextPos, Int($iAddInfo))
		Case 1 ; negative unsigned int - no content
			If $iAddInfoLen > 1 Then $iAddInfo = _cbor_swapEndianess($iAddInfo)
			Return SetExtended($dNextPos, -1 - Int($iAddInfo))
		Case 2 ; byte string           - N bytes
			Return SetExtended($dNextPos + $iAddInfo, BinaryMid($dInput, $dNextPos, $iAddInfo))
		Case 3 ; text string           - N bytes (as utf-8)
			Return SetExtended($dNextPos + $iAddInfo, BinaryToString(BinaryMid($dInput, $dNextPos, $iAddInfo), 4))
		Case 4 ; array                 - N data items (elements)
			; Todo: If $bIndefinite Then --> indefinite length array
			Local $aArray[$iAddInfo]
			For $i = 0 To $iAddInfo - 1
				$aArray[$i] = _cbor_decode($dInput, $dNextPos)
				$dNextPos = @extended
			Next
			Return SetExtended($dNextPos, $aArray)
		Case 5 ; map                   - 2 N data items (key/value pairs)
			; Todo: If $bIndefinite Then --> indefinite length map
			Local $mMap[], $sKey, $vVal
			For $i = 0 To $iAddInfo - 1
				$sKey = _cbor_decode($dInput, $dNextPos)
				$dNextPos = @extended

				$vVal = _cbor_decode($dInput, $dNextPos)
				$dNextPos = @extended

				$mMap[$sKey] = $vVal
			Next
			Return SetExtended($dNextPos, $mMap)
		case 6 ; tag of number N       - 1 data item
			;  ConsoleWrite("Type: " & "tag of number N" & @CRLF)
		case 7 ; simple / float        - no content
				If $iAddInfoLen = 1 AND Int($iAddInfo) < 32 Then ; simple type
				Switch Int(BitAND($dInitByte, 31))
					Case 20
						Return SetExtended($dNextPos, False)
					Case 21
						Return SetExtended($dNextPos, True)
					Case 22
						Return SetExtended($dNextPos, Null)
					Case 23 ; officially "undefined" but in AutoIt we map it to "Default"
						Return SetExtended($dNextPos, Default)
					Case 31 ; break stop-code for indefinite length items (currently not supported)
						; should return a special value which can be used to detect the indefinite length end in array or map branch
						Return SetError(3, $iAddInfo, Null)
					Case Else
					; unassigned(0..19) reserved (24..31) and unassigned (32..255) values
				EndSwitch
			Else ; float type (32 or 64 Bit IEEE754 - 16 Bit is not supported here)
				$iAddInfo = _cbor_swapEndianess($iAddInfo)

				Switch $iAddInfoLen
					Case 2 ; half float
						Return SetExtended($dNextPos, __cbor_hpToFloat($iAddInfo))
					Case 4 ; float
						Local $tTmp = DllStructCreate("Byte[4]")
						DllStructSetData($tTmp, 1, $iAddInfo)

						; convert the raw bytes
						Local $tFloat = DllStructCreate("FLOAT", DllStructGetPtr($tTmp))

						Return SetExtended($dNextPos, DllStructGetData($tFloat, 1))
					Case 8 ; double
						Local $tTmp = DllStructCreate("Byte[8]")
						DllStructSetData($tTmp, 1, $iAddInfo)

						; convert the raw bytes
						Local $tFloat = DllStructCreate("DOUBLE", DllStructGetPtr($tTmp))

						Return SetExtended($dNextPos, DllStructGetData($tFloat, 1))
					Case Else
						Return SetError(6, $iAddInfoLen, Null) ; exception: no valid float type (half-float, float or double)
				EndSwitch
			EndIf
	EndSwitch
EndFunc






Func _cbor_encode(ByRef $vInput)

EndFunc

; change the endianess of a binary from big-endian to little-endian (windows-endianess) - or vice versa
Func _cbor_swapEndianess($dBig)
    Local Static $hDll = DllOpen("ws2_32.dll")

    Switch BinaryLen($dBig)
        Case 2
            Local $aRet = DllCall($hDll, "USHORT", "ntohs", "USHORT", $dBig)
            Return @error ? SetError(2, @error, Null) : BinaryMid($aRet[0], 1, 2)            ;  BinaryMid(Binary(BitAnd(BitShift($dBig, 8), 255) + BitShift(BitAnd($dBig, 255), -8)), 1, 2)
        Case 4
            Local $aRet = DllCall($hDll, "ULONG", "ntohl", "ULONG", $dBig)
            Return @error ? SetError(2, @error, Null) : Number($aRet[0], 1)
        Case 8
            Local $aRetHigh = DllCall($hDll, "ULONG", "ntohl", "ULONG", BinaryMid($dBig, 1, 4))
            IF @error Then Return SetError(3, @error, Null)

            Local $aRetLow = DllCall($hDll, "ULONG", "ntohl", "ULONG", BinaryMid($dBig, 5, 4))
            IF @error Then Return SetError(4, @error, Null)

            Local $t64Bit = DllStructCreate("ULONG;ULONG")
            DllStructSetData($t64Bit, 1, $aRetLow[0])
            DllStructSetData($t64Bit, 2, $aRetHigh[0])

            Local $tReturn = DllStructCreate("UINT64", DllStructGetPtr($t64Bit))
            Return DllStructGetData($tReturn, 1)

        Case Else
            Local $iLen = BinaryLen($dBig)

            Local $tBytes = DllStructCreate("BYTE[" & $iLen & "]")
            Local $iTargetPos = $iLen, $i
            For $i = 1 To $iLen
                DllStructSetData($tBytes, 1, BinaryMid($dBig, $i, 1), $iTargetPos)
                $iTargetPos -= 1
            Next
            Return DllStructGetData($tBytes, 1)
    EndSwitch
EndFunc


; take 2 binary bytes and interprete them as IEEE 754 half precision float (FP16)
Func __cbor_hpToFloat($dBin)
	; Todo: special exponents: 00000 = zero/-0; 11111 = +-infinity, NaN
	Local $iSign = BitShift(BitAND($dBin, 32768), 15)
	Local $iExponent = BitAnd(BitShift($dBin, 10), 31) - 15
    Local $iFraction = BitAnd($dBin, 1023)

    Local $fFraction = 1, $fCurVal = 0.0009765625, $iCurBitVal = 1, $i

    If $iExponent = -15 Then ; special case when exponent = 00000 defined in IEEE 754
        $iExponent = -14
        $fFraction = 0
    EndIf

	; calculate the fraction:
    For $i = 0 To 9
        If BitAnd($iFraction, $iCurBitVal) Then
			$fFraction += $fCurVal
		EndIf
		$fCurVal += $fCurVal
		$iCurBitVal += $iCurBitVal
	Next

	Return ($iSign ? -1 : 1) * (2^$iExponent) * $fFraction
EndFunc