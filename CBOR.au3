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
	Local $iAddInfoLen = 0
	Local $bIndefinite = False
	Switch $iAddInfo
		Case 0 To 23
			;  $iAddInfo = $iAddInfo+
			;  $iAddInfoLen = 0
		Case 24 ; following byte
			$iAddInfoLen = 1
			$iAddInfo = BinaryMid($dInput, $dNextPos, 1)
			$dNextPos += 1
		Case 25 To 27 ; following 2,4,8 Bytes
			$iAddInfoLen = 2^($iAddInfo-24)
			$iAddInfo = _cbor_swapEndianess(BinaryMid($dInput, $dNextPos, $iAddInfoLen)) ; cbor is big-endian but Windows (Intel) is little-endian
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
			Return SetExtended($dNextPos, Int($iAddInfo))
		Case 1 ; negative unsigned int - no content
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
			Local $mMap[], $vKey, $vVal
			For $i = 0 To $iAddInfo - 1
				$vKey = _cbor_decode($dInput, $dNextPos)
				$dNextPos = @extended

				$vVal = _cbor_decode($dInput, $dNextPos)
				$dNextPos = @extended

				$mMap[$vKey] = $vVal
			Next
			Return SetExtended($dNextPos, $mMap)
		case 6 ; tag of number N       - 1 data item
			; just ignore the tag value:
			Return _cbor_decode($dInput, $dNextPos)
		case 7 ; simple / float        - no content
				If $iAddInfoLen = 0 AND Int($iAddInfo) < 32 Then ; simple type
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
			Else ; float type (16, 32 or 64 Bit IEEE754)
				Switch $iAddInfoLen
					Case 2 ; half float
						Return SetExtended($dNextPos, __cbor_FP16ToFP64($iAddInfo))
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


; take 2 binary bytes and interprete them as IEEE 754 half precision float (FP16) and convert this to FP64 (Double)
Func __cbor_FP16ToFP64($dBin)
	$dBin = Int($dBin, 1)

	; like a union in C: same data - different interpretation:
	Local $tULONG = DllStructCreate("ULONG")
	Local $tFloat = DllStructCreate("FLOAT", DllStructGetPtr($tULONG))

	; extract components
	Local Const $e = BitShift(BitAND($dBin, 0x7C00), 10) ; exponent
	Local Const $m = BitShift(BitAND($dBin, 0x03FF), -13) ; mantissa
	DllStructSetData($tFloat, 1, $m)
	Local Const $v = BitShift(DllStructGetData($tULONG, 1), 23) ; leading zeros in denormalized format

	; special case treatment (+-infinity, NaN)
	If $e = 31 Then	Return $m = 0 _
			? ($dBin > 0x8000 ? -1.0 / 0.0 : 1.0 / 0.0) _ ; +-infinity
			: 0.0 / 0.0 ; NaN

	; the main conversion
	DllStructSetData($tULONG, 1, BitOr( _
		BitShift(BitAnd($dBin, 0x8000), -16), _
		($e <> 0) * BitOr(BitShift($e + 112, -23), $m), _
		BitAnd($e = 0, $m <> 0) * BitOr(BitShift($v - 37, -23), BitAnd(BitShift($m, 150 - $v), 0x007FE000) ) _
	))

	Return  DllStructGetData($tFloat, 1)
EndFunc

; take float variable and convert it to FP16-Format
Func __cbor_FloatToFP16($vNumber)
	; like a union in C: same data - different interpretation:
	Local $tULONG = DllStructCreate("ULONG")
	Local $tFloat = DllStructCreate("FLOAT", DllStructGetPtr($tULONG))

	; convert input into a 32 Bit Float first (bit-operations in AutoIt can only handle 32 bit-values):
	DllStructSetData($tFloat, 1, $vNumber)
	Local $iNumber = DllStructGetData($tULONG, 1)

	Local Const $b = $iNumber + 0x800 ; round-to-nearest-even: add last bit after truncated mantissa
	Local Const $e = BitShift(BitAND($b, 0x7F800000), 23) ; exponent
	Local Const $m = BitAND($b, 0x007FFFFF) ; mantissa; in line below: 0x007FF000 = 0x00800000-0x00001000 = decimal indicator flag - initial rounding

	Local $iReturn = BitOR( _
		BitShift(BitAnd($b, 0x80000000), 16), _
		($e > 112) *  BitOr(BitAnd(BitShift($e - 112, -10), 0x7C00), BitShift($m, 13)), _
		BitAnd($e < 113, $e > 101) *  BitShift(BitShift(0x007FF000 + $m, 125 - $e) + 1, 1), _
		($e > 143) * 0x7FFF _
	)
	Return BinaryMid($iReturn, 1, 2)
EndFunc
