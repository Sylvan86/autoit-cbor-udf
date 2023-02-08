#include-once

; #INDEX# =======================================================================================================================
; Title .........: CBOR-UDF
; Version .......: 0.1
; AutoIt Version : 3.3.16.1
; Language ......: english (german maybe by accident)
; Description ...: functions encoding AutoIt-variables into CBOR-formatted binary and vice versa
; Author(s) .....: AspirinJunkie
; Last changed ..: 2023-02-07
; Remarks .......: The UDF is oriented on RFC 8949, but does not claim to be fully implemented. (https://www.rfc-editor.org/rfc/rfc8949.html)
;                  especially these CBOR-features are not not implemented yet:
;                     - tags (to mark date/time strings etc.) - tag elements are simply ignored
;                     - bytewise lexicographic order of the map-keys
;                     - UINT64, bigfloats, bignums etc. due to the lack of corresponding autoit datatypes
;                     - indefinite length for arrays, maps, byte strings and text strings - in this case the conversion fails
;                     - "undefined" - is mapped to/from "Default"-keyword because AutoIt don't know a "undefined"-keyword
; ===============================================================================================================================

; #Function list# =======================================================================================================================
; ---- import and export from or to cbor ------
;  _cbor_encode              - converts a (nested) AutoIt data structure into a CBOR binary
;  _cbor_decode              - converts a CBOR binary into a (nested) AutoIt data structure
;
; ---- Thematically related helper functions ---------
; __cbor_FloatToFP16         - convert a AutoIt-float-variable into a IEE 754 16-Bit floating point number
; __cbor_floatToFP32         - convert a AutoIt-float-variable into a IEE 754 32-Bit floating point number
; __cbor_FP16ToFP64          - convert a IEE 754 16-Bit floating point number into a AutoIt-float-variable
; __cbor_swapEndianess       - swaps the endianess of a binary (little-endian to big-endian and vice-versa)
; __cbor_A2DToAinA           - converts a 2D array into a Arrays in Array
;
; ---- purely supportive functions ----
; __cbor_StructToBin         - create a binary variable out of a AutoIt-DllStruct
; __cbor_encodeNum           - builds the initial byte[s] of a cbor-element and the structure
; ===============================================================================================================================






; #FUNCTION# ======================================================================================
; Name ..........: _cbor_decode
; Description ...: converts a CBOR binary into a (nested) AutoIt data structure
; Syntax ........: _cbor_decode($dInput [$iCurPos = 1])
; Parameters ....: $dInput        - a CBOR formatted binary
;                  [$iCurPos]     - don't touch - for internal recursive processing
; Return values .: Success - Return a nested structure of AutoIt-datatypes
;                       @extended = next byte index / binary len of $dInput
;                  Failure - Return Null and set @error to:
;        				@error = 1 - no valid value for additional info - not defined in bcor standard yet - only reserved for later
;                              = 2 - invalid combination of major type and additional info
;                              = 3 - indefinite length is not supported yet
;                              = 4 - no valid float type (half-float, float or double)
; Author ........: AspirinJunkie
; =================================================================================================
Func _cbor_decode($dInput, $iCurPos = 1)
	Local $dInitByte = BinaryMid($dInput, $iCurPos, 1)
	Local $iMajorType = Int(Bitshift($dInitByte, 5)) ; only 0-7 possible - so no extra range check
	Local $dNextPos = $iCurPos + 1

	; read out the additional info:
	Local $iAddInfo = Int(BitAND($dInitByte, 31))
	Local $iAddInfoLen = 0
	Local $bIndefinite = False
	Switch $iAddInfo
		Case 0 To 23
			;  $iAddInfo = $iAddInfo
			;  $iAddInfoLen = 0
		Case 24 ; following byte
			$iAddInfoLen = 1
			$iAddInfo = Int(BinaryMid($dInput, $dNextPos, 1))
			$dNextPos += 1
		Case 25 To 27 ; following 2,4,8 Bytes
			$iAddInfoLen = 2^($iAddInfo-24)
			$iAddInfo = Int(__cbor_swapEndianess(BinaryMid($dInput, $dNextPos, $iAddInfoLen))) ; cbor is big-endian but Windows (Intel) is little-endian
			$dNextPos += $iAddInfoLen
		Case 28 To 30
			Return SetError(1, $iAddInfo, Null) ; exception: no valid value for additional info - not defined in bcor standard yet - only reserved for later
		Case 31 ; indefinite-length array or map (currently not supported)
			$bIndefinite = True
			;  If ($dInitByte < 2) Or ($dInitByte = 6) Then Return SetError(3, $dInitByte, Null) ; exception: invalid combination of major type and additional info
			Return SetError(2, $iAddInfo, Null)
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
						Return SetError(4, $iAddInfoLen, Null) ; exception: no valid float type (half-float, float or double)
				EndSwitch
			EndIf
	EndSwitch
EndFunc


; #FUNCTION# ======================================================================================
; Name ..........: _cbor_encode
; Description ...: converts a (nested) AutoIt data structure into a CBOR binary
; Syntax ........: _cbor_encode($vObject)
; Parameters ....: $vObject       - (nested) AutoIt data structure (integer/float/string/binary/bool/keyword/array(1D/2D)/map/dictionary)
; Return values .: Success - Return a CBOR-formatted binary
;                       @extended = next byte index / binary len of $dInput
;                  Failure - Return Null and set @error to:
;        				@error = 1 - invalid dimensions of array - only 1D or 2D-arrays are allowed (but nested arrays are possible)
;                              = 2 - unsupported variable type
; Author ........: AspirinJunkie
; =================================================================================================
Func _cbor_encode($vObject)
	Switch VarGetType($vObject)
		Case "String"
			Local $bString = StringToBinary($vObject, 4) ; must be UTF-8 in CBOR
			Local $iBinLen = BinaryLen($bString)

			; build the whole element structure (initial element byte + size information + data)
			Local $tRet = __cbor_encodeNum($iBinLen, 3, ";BYTE[" & $iBinLen & "]")
			Local $iDataIndex = @extended > 0 ? 3 : 2
			DllStructSetData($tRet, $iDataIndex, $bString)

			Return __cbor_StructToBin($tRet)
		Case "Int32", "Int64"
			Local $bNeg = $vObject < 0 ? True : False
			If $bNeg Then $vObject = -$vObject - 1

			$tRet = __cbor_encodeNum($vObject, $bNeg ? 1 : 0)
			Return __cbor_StructToBin($tRet)

		Case "Float", "Double"
			Local $bCborFirst = 0xE0
			Local $fFP64 = Number($vObject, 3)
			Local $fFP32 = __cbor_FloatToFP32($vObject)

			If $fFP64 <> $fFP32 Then ; FP64
				$bCborFirst += 27

				Local $tRet = DllStructCreate("BYTE;BYTE[8]")
				Local $tFloat = DllStructCreate("DOUBLE", DllStructGetPtr($tRet, 2))
				DllStructSetData($tFloat, 1, $fFP64)
				DllStructSetData($tRet, 2, __cbor_swapEndianess(DllStructGetData($tRet, 2)))
			Else
				Local $bFP16 = __cbor_FloatToFP16($vObject)
				Local $fFP16 = __cbor_FP16ToFP64($bFP16)

				If $fFP32 <> $fFP16 Then ; FP32
					$bCborFirst += 26

					Local $tRet = DllStructCreate("BYTE;BYTE[4]")
					Local $tFloat = DllStructCreate("FLOAT", DllStructGetPtr($tRet, 2))
					DllStructSetData($tFloat, 1, $fFP32)
					DllStructSetData($tRet, 2, __cbor_swapEndianess(DllStructGetData($tRet, 2)))
				Else ; FP 16
					$bCborFirst += 25

					Local $tRet = DllStructCreate("BYTE;BYTE[2]")
					DllStructSetData($tRet, 2, __cbor_swapEndianess($bFP16))
				EndIf
			EndIf
			DllStructSetData($tRet, 1, $bCborFirst)
			Return __cbor_StructToBin($tRet)

		Case "Bool"
			Return $vObject ? BinaryMid(0xF5, 1, 1) : BinaryMid(0xF4, 1, 1)

		Case "Keyword"
			Return IsKeyword($vObject) = 2 ? BinaryMid(0xF6, 1, 1) : BinaryMid(0xF7, 1, 1)    ; ? null : Default/undefined

		Case "Binary"
			Local $iBinLen = BinaryLen($vObject)
			If $iBinLen = 0 Then Return BinaryMid(0x40, 1, 1)

			; build the whole element structure (initial element byte + size information + data)
			$tRet = __cbor_encodeNum($iBinLen, 2, ";BYTE[" & $iBinLen & "]")
			Local $iDataIndex = @extended > 0 ? 3 : 2
			DllStructSetData($tRet, $iDataIndex, $vObject)
			Return __cbor_StructToBin($tRet)

		Case "Array"
			If UBound($vObject, 0) > 2 Then Return SetError(1, UBound($vObject, 0), Null)
			If UBound($vObject, 0) = 2 Then $vObject = __cbor_A2DToAinA($vObject)
			Local $nElements = UBound($vObject)
			Local $aBinElements[$nElements]
			Local $bElement

			; encode all elements:
			Local $tagElements = ""
			For $i = 0 To $nElements - 1
				$bElement = _cbor_encode($vObject[$i])
				If @error Then Return SetError(@error, @extended, Null)
				$aBinElements[$i] = $bElement
				$tagElements &= ";BYTE" & (BinaryLen($bElement) > 1 ? "[" & BinaryLen($bElement) & "]" : "" )
			Next

			; build the whole element structure (initial element byte + size information + data)
			Local $tRet = __cbor_encodeNum($nElements, 4, $tagElements)
			Local $iOffset = @extended > 0 ? 3 : 2

			; write elements
			For $i = 0 To $nElements - 1
				DllStructSetData($tRet, $i + $iOffset, $aBinElements[$i])
			Next

			Return __cbor_StructToBin($tRet)

		Case "Object"
			If ObjName($vObject) = "Dictionary" Then
				Local $nElements = $vObject.Count()
				If $nElements = 0 Then Return BinaryMid(0xA0, 1, 1)

				Local $aBinElements[$nElements][2]
				Local $tRet, $vKey, $bKey, $bValue

				; encode all elements:
				Local $tagElements = "", $i = 0
				;  For $vKey In MapKeys($vObject)
				For $vKey In $vObject.Keys
					$bKey = _cbor_encode($vKey)
					If @error Then Return SetError(@error, @extended, Null)
					$bValue = _cbor_encode($vObject($vKey))
					If @error Then Return SetError(@error, @extended, Null)
					$aBinElements[$i][0] = $bKey
					$aBinElements[$i][1] = $bValue

					$tagElements &= ";BYTE" & (BinaryLen($bKey) > 1 ? "[" & BinaryLen($bKey) & "]" : "" ) & _
									";BYTE" & (BinaryLen($bValue) > 1 ? "[" & BinaryLen($bValue) & "]" : "" )
					$i += 1
				Next

				; build the whole element structure (initial element byte + size information + data)
				$tRet = __cbor_encodeNum($nElements, 5, $tagElements)
				Local $iOffset = @extended > 0 ? 3 : 2

				; write elements
				For $i = 0 To $nElements - 1
					DllStructSetData($tRet, $i + $i + $iOffset, $aBinElements[$i][0])
					DllStructSetData($tRet, $i + $i + 1 + $iOffset, $aBinElements[$i][1])
				Next

				Return __cbor_StructToBin($tRet)
			Else
				Return SetError(2, 0, Null)
			EndIf

		Case "Map"
			Local $nElements = UBound($vObject)
			Local $aBinElements[$nElements][2]
			Local $tRet, $vKey, $bKey, $bValue

			If $nElements = 0 Then Return BinaryMid(0xA0, 1, 1)

			; encode all elements:
			Local $tagElements = "", $i = 0
			For $vKey In MapKeys($vObject)
				$bKey = _cbor_encode($vKey)
				If @error Then Return SetError(@error, @extended, Null)
				$bValue = _cbor_encode($vObject[$vKey])
				If @error Then Return SetError(@error, @extended, Null)
				$aBinElements[$i][0] = $bKey
				$aBinElements[$i][1] = $bValue

				$tagElements &= ";BYTE" & (BinaryLen($bKey) > 1 ? "[" & BinaryLen($bKey) & "]" : "" ) & _
								";BYTE" & (BinaryLen($bValue) > 1 ? "[" & BinaryLen($bValue) & "]" : "" )
				$i += 1
			Next

			; build the whole element structure (initial element byte + size information + data)
			$tRet = __cbor_encodeNum($nElements, 5, $tagElements)
			Local $iOffset = @extended > 0 ? 3 : 2

			; write elements
			For $i = 0 To $nElements - 1
				DllStructSetData($tRet, $i + $i + $iOffset, $aBinElements[$i][0])
				DllStructSetData($tRet, $i + $i + 1 + $iOffset, $aBinElements[$i][1])
			Next

			Return __cbor_StructToBin($tRet)
		Case Else
			Return SetError(2, 0, Null)
	EndSwitch
EndFunc

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_swapEndianess
; Description ...: swaps the endianess of a binary (little-endian to big-endian and vice-versa)
; Syntax ........: __cbor_swapEndianess($dBig)
; Parameters ....: $dBig       - binary which should be converted
; Return values .: Success     - Return a binary with swapped endianess
;                  Failure      - Return Null and set @error to:
;        				@error = 1 - error during calling ntohs
;                              = 2 - error during calling ntohl
;                              = 3 - error during calling ntohl processing the higher bytes of 64 Bit-data
;                              = 4 - error during calling ntohl processing the lower bytes of 64 Bit-data
; Author ........: AspirinJunkie
; =================================================================================================
Func __cbor_swapEndianess($dBig)
    Local Static $hDll = DllOpen("ws2_32.dll")

    Switch BinaryLen($dBig)
        Case 2
            Local $aRet = DllCall($hDll, "USHORT", "ntohs", "USHORT", $dBig)
            Return @error ? SetError(1, @error, Null) : BinaryMid($aRet[0], 1, 2)            ;  BinaryMid(Binary(BitAnd(BitShift($dBig, 8), 255) + BitShift(BitAnd($dBig, 255), -8)), 1, 2)
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

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_StructToBin
; Description ...: create a binary variable out of a AutoIt-DllStruct
; Syntax ........: __cbor_StructToBin(ByRef $tStruct)
; Parameters ....: $tStruct    - DllStruct where you want the binary expression from
; Return values .: Success     - Return a binary with the dllstruct-content as data
; Author ........: AspirinJunkie
; =================================================================================================
Func __cbor_StructToBin(ByRef $tStruct)
	Local $tReturn = DllStructCreate("Byte[" & DllStructGetSize($tStruct) & "]", DllStructGetPtr($tStruct))
	Return DllStructGetData($tReturn, 1)
EndFunc

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_FP16ToFP64
; Description ...: convert a IEE 754 16-Bit floating point number into a AutoIt-float-variable
; Syntax ........: __cbor_FP16ToFP64($dBin)
; Parameters ....: $dBin    - 2Byte Binary (or anything convertible into that) with IEEE754-FP16-formatted float-number
; Return values .: Success     - Return a AutoIt float variable
; Author ........: AspirinJunkie
; Remarks .......: Algorithm based on this paper: https://www.researchgate.net/publication/362275548_Accuracy_and_performance_of_the_lattice_Boltzmann_method_with_64-bit_32-bit_and_customized_16-bit_number_formats
; =================================================================================================
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

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_FloatToFP16
; Description ...: take float variable and convert it to IEEE754 FP16-Format
; Syntax ........: __cbor_FloatToFP16($vNumber)
; Parameters ....: $vNumber - AutoIt float-variable
; Return values .: Success  - Return a 2-Byte binary with number in IEEE754 FP16-format
; Author ........: AspirinJunkie
; Remarks .......: Algorithm based on this paper: https://www.researchgate.net/publication/362275548_Accuracy_and_performance_of_the_lattice_Boltzmann_method_with_64-bit_32-bit_and_customized_16-bit_number_formats
; =================================================================================================
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

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_FloatToFP32
; Description ...: convert a AutoIt-float-variable into a IEE 754 32-Bit floating point number
; Syntax ........: __cbor_FloatToFP32($vDouble)
; Parameters ....: $vDouble - AutoIt double-variable
; Return values .: Success  - Return the value of a FP32-Float-variable
; Author ........: AspirinJunkie
; =================================================================================================
Func __cbor_FloatToFP32($vDouble)
	Local $tFloat = DllStructCreate("FLOAT")
	DllStructSetData($tFloat, 1, $vDouble)
	Return DllStructGetData($tFloat, 1)
EndFunc

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_encodeNum
; Description ...: helper function for building the initial byte[s] of a cbor-element
; Syntax ........: __cbor_encodeNum($iNum, $iMajortype [, $sTagAdditional = ""])
; Parameters ....: $iNum           - number of elements which should be encoded in cbor-style
;                  $iMajortype     - 0..7 = CBOR major types
;                  $sTagAdditional - additional dll-struct-definition to build the whole element struct
; Return values .: Success  - DllStruct to be used as cbor-element
; Author ........: AspirinJunkie
; =================================================================================================
Func __cbor_encodeNum($iNum, $iMajortype, $sTagAdditional = "")
	Local $bCborFirst = BitShift($iMajortype, -5)
	Local $iExt = 0, $tRet

	;  encode the number of elements
	Switch $iNum
		Case 0 ; empty
			$tRet = DllStructCreate("BYTE")
		Case 1 To 23 ; direct count
			$bCborFirst += $iNum
			$tRet = DllStructCreate("BYTE" & $sTagAdditional)
		Case 24 To 255 ; 1 Byte
			$bCborFirst += 24
			$tRet = DllStructCreate("BYTE;BYTE" & $sTagAdditional)
			DllStructSetData($tRet, 2, $iNum)
			$iExt = 1
		Case 256 To 65535 ; 2 Byte
			$bCborFirst += 25
			$tRet = DllStructCreate("BYTE;BYTE[2]" & $sTagAdditional)
			DllStructSetData($tRet, 2, __cbor_swapEndianess(BinaryMid($iNum, 1, 2)))
			$iExt = 2
		Case 65536 To 4294967295 ; 4 Byte
			$bCborFirst += 26
			$tRet = DllStructCreate("BYTE;BYTE[4]" & $sTagAdditional)
			DllStructSetData($tRet, 2, __cbor_swapEndianess(BinaryMid($iNum, 1, 4)))
			$iExt = 4
		Case Else ; 8 Byte
			$bCborFirst += 27
			$tRet = DllStructCreate("BYTE;BYTE[8]" & $sTagAdditional)
			DllStructSetData($tRet, 2, __cbor_swapEndianess($iNum))
			$iExt = 8
	EndSwitch
	DllStructSetData($tRet, 1, $bCborFirst)

	Return SetExtended($iExt, $tRet)
EndFunc

; #FUNCTION# ======================================================================================
; Name ..........: __cbor_A2DToAinA()
; Description ...: Convert a 2D array into a Arrays in Array
; Syntax ........: __cbor_A2DToAinA(ByRef $A)
; Parameters ....: $A             - the 2D-Array  which should be converted
; Return values .: Success: a Arrays in Array build from the input array
;                  Failure: False
;                     @error = 1: $A is'nt an 2D array
; Author ........: AspirinJunkie
; =================================================================================================
Func __cbor_A2DToAinA(ByRef $A, $bTruncEmpty = True)
	If UBound($A, 0) <> 2 Then Return SetError(1, UBound($A, 0), False)
	Local $N = UBound($A), $u = UBound($A, 2)
	Local $a_Ret[$N]

	IF $bTruncEmpty Then
		For $i = 0 To $N - 1
			Local $x = $u -1
			While IsString($A[$i][$x]) And $A[$i][$x] = ""
				$x -= 1
			WEnd
			Local $t[$x+1]
			For $j = 0 To $x
				$t[$j] = $A[$i][$j]
			Next
			$a_Ret[$i] = $t
		Next
	Else
		For $i = 0 To $N - 1
			Local $t[$u]
			For $j = 0 To $u - 1
				$t[$j] = $A[$i][$j]
			Next
			$a_Ret[$i] = $t
		Next
	EndIf
	Return $a_Ret
EndFunc   ;==>__cbor_A2DToAinA