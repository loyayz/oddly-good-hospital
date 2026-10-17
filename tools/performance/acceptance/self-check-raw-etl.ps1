#requires -Version 7.0
# Compilation and synthetic bytes/marshalling only. No ETL/session API invoked.
param([string]$Output='')
$ErrorActionPreference='Stop'
if(-not ('HospitalRawEtlReader' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'decode-etl.cs')}
$passed=[Collections.Generic.List[string]]::new()
function Check([string]$Name,[bool]$Condition){if(-not $Condition){throw "Synthetic check failed: $Name"};$passed.Add($Name)}
function New-FixedSchema([string]$Body){[HospitalRawEtlReader+EventSchema]::new(33,3,21,1,'AdapterAllocation',('<template xmlns="http://schemas.microsoft.com/win/2004/08/events">'+$Body+'</template>'))}
$layout=[HospitalRawEtlReader]::Layout()
Check 'Windows x64 native structure sizes/offsets' ($layout['event_record_size'] -eq 112 -and $layout['logfile_size'] -eq 448 -and $layout['trace_header_perffreq'] -eq 256)
$schema=New-FixedSchema '<data name="hProcessId" inType="win:Pointer"/><data name="physical" inType="win:UInt16"/><data name="flag" inType="win:Boolean"/><data name="allocSize" inType="win:UInt64"/>'
$bytes=[Collections.Generic.List[byte]]::new()
$bytes.AddRange([BitConverter]::GetBytes([uint64]9000));$bytes.AddRange([BitConverter]::GetBytes([uint16]2));$bytes.AddRange([BitConverter]::GetBytes([uint32]1));$bytes.AddRange([BitConverter]::GetBytes([uint64]::MaxValue))
$decoded=[HospitalRawEtlReader]::DecodePayload($schema,$bytes.ToArray(),0x40,8)
Check 'packed unaligned UINT16/BOOL/UINT64 and exact uint64' ($decoded.Status -eq 'decoded' -and $decoded.Data['allocSize'] -eq '18446744073709551615' -and $decoded.Consumed -eq 22 -and $decoded.Data['flag'] -eq 'true')
$pointer=New-FixedSchema '<data name="p" inType="win:Pointer"/>'
$decoded32=[HospitalRawEtlReader]::DecodePayload($pointer,[BitConverter]::GetBytes([uint32]::MaxValue),0x20,8)
Check '32bit event flags override 64bit trace pointer size' ($decoded32.Status -eq 'decoded' -and $decoded32.PointerSize -eq 4 -and $decoded32.Data['p'] -eq '0xffffffff')
$fallback=[HospitalRawEtlReader]::DecodePayload($pointer,[BitConverter]::GetBytes([uint32]11),0,4)
Check 'header flags absent use explicit trace pointer size' ($fallback.Status -eq 'decoded' -and $fallback.Data['p'] -eq '0x0000000b')
$conflict=[HospitalRawEtlReader]::DecodePayload($pointer,$bytes.ToArray(),0x60,8)
Check 'conflicting pointer flags are incomplete' ($conflict.Status -eq 'incomplete' -and $conflict.Data.Count -eq 0)
$short=[HospitalRawEtlReader]::DecodePayload($schema,$bytes.ToArray()[0..20],0x40,8)
Check 'truncated payload never publishes partial data map' ($short.Status -eq 'incomplete' -and $short.Data.Count -eq 0 -and $short.Fields.Count -gt 0)
$long=[byte[]]($bytes.ToArray()+[byte]0)
$extra=[HospitalRawEtlReader]::DecodePayload($schema,$long,0x40,8)
Check 'trailing bytes are incomplete' ($extra.Status -eq 'incomplete' -and $extra.Data.Count -eq 0)
$unknown=New-FixedSchema '<data name="x" inType="win:SID"/>'
Check 'unknown type rejected' ([HospitalRawEtlReader]::DecodePayload($unknown,[byte[]]@(),0x40,8).Status -eq 'incomplete')
$array=New-FixedSchema '<data name="x" inType="win:UInt32" count="NumItems"/>'
Check 'dynamic array not guessed' ($null -ne $array.Error)
$bounded=New-FixedSchema '<data name="ConfigSpaceSize" inType="win:UInt32"/><data name="ConfigSpace" inType="win:UInt8" count="ConfigSpaceSize"/><data name="VendorID" inType="win:UInt32"/><data name="AdapterLuid" inType="win:UInt64"/>'
$arrayBytes=[byte[]]([BitConverter]::GetBytes([uint32]2)+[byte[]]@(18,52)+[BitConverter]::GetBytes([uint32]32902)+[BitConverter]::GetBytes([uint64]::MaxValue))
$arrayResult=[HospitalRawEtlReader]::DecodePayload($bounded,$arrayBytes,0x40,8)
Check 'bounded UInt8 array preserves bytes and following identity offsets' ($arrayResult.Status -eq 'decoded' -and $arrayResult.Data['ConfigSpace'] -eq 'EjQ=' -and $arrayResult.Data['VendorID'] -eq '32902' -and $arrayResult.Data['AdapterLuid'] -eq '18446744073709551615' -and $arrayResult.Fields[1]['count'] -eq 2 -and $arrayResult.Fields[1]['encoding'] -eq 'base64')
$emptyArray=[byte[]]([BitConverter]::GetBytes([uint32]0)+[BitConverter]::GetBytes([uint32]32902)+[BitConverter]::GetBytes([uint64]17))
Check 'zero length UInt8 array consumes no following bytes' ([HospitalRawEtlReader]::DecodePayload($bounded,$emptyArray,0x40,8).Data['AdapterLuid'] -eq '17')
$excessArray=[byte[]]([BitConverter]::GetBytes([uint32]70000)+[byte[]]@(18,52))
$excessResult=[HospitalRawEtlReader]::DecodePayload($bounded,$excessArray,0x40,8)
Check 'array count beyond payload bound clears parsed prefix' ($excessResult.Status -eq 'incomplete' -and $excessResult.Data.Count -eq 0)
$forward=New-FixedSchema '<data name="ConfigSpace" inType="win:UInt8" count="ConfigSpaceSize"/><data name="ConfigSpaceSize" inType="win:UInt32"/>'
Check 'forward array count is unsupported' ($null -ne $forward.Error)
$duplicate=New-FixedSchema '<data name="x" inType="win:UInt32"/><data name="x" inType="win:UInt32"/>'
Check 'duplicate schema keys rejected' ($null -ne $duplicate.Error)
$utf=New-FixedSchema '<data name="text" inType="win:UnicodeString"/>'
$utfBytes=[Text.Encoding]::Unicode.GetBytes("医院😀`0")
Check 'UTF16 bounded terminator and nonBMP' ([HospitalRawEtlReader]::DecodePayload($utf,$utfBytes,0x40,8).Data['text'] -eq '医院😀')
Check 'UTF16 missing terminator rejected' ([HospitalRawEtlReader]::DecodePayload($utf,[byte[]]@(65,0),0x40,8).Status -eq 'incomplete')
$row=[HospitalRawEtlReader]::SyntheticRecordJson($schema,$bytes.ToArray(),0x40,9007199254740993,1,8)|ConvertFrom-Json -AsHashtable
Check 'raw QPC >2^53 retained as integer' ($row.qpc_ticks -eq 9007199254740993 -and $row.raw_timestamp -eq 9007199254740993 -and $row.qpc_frequency -eq 10000000)
Check 'payload ownership distinct from header PID/TID' ($row.header_pid -eq 4242 -and $row.header_tid -eq 7 -and $row.data.hProcessId -eq '0x0000000000002328')
Check 'raw payload base64 lossless' ([Convert]::ToBase64String($bytes.ToArray()) -eq $row.user_data_base64)
$notQpc=[HospitalRawEtlReader]::SyntheticRecordJson($schema,$bytes.ToArray(),0x40,12345,2,8)|ConvertFrom-Json -AsHashtable
Check 'nonQPC timestamp not mislabeled QPC' ($null -eq $notQpc.qpc_ticks -and $notQpc.raw_timestamp -eq 12345 -and $notQpc.clock_domain -eq 'raw_etw_clock_2')
$summary=@{kind='synthetic_raw_etl_checks';passed=$passed.ToArray();count=$passed.Count;native_trace_api_invoked=$false;etl_read=$false;game_run=$false;source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'decode-etl.cs') -Algorithm SHA256).Hash.ToLowerInvariant();layout=$layout;utc=[DateTime]::UtcNow.ToString('o')}
if($Output){
    $destination=[IO.Path]::GetFullPath($Output)
    $stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
    try{$encoded=[Text.UTF8Encoding]::new($false).GetBytes(($summary|ConvertTo-Json -Depth 8));$stream.Write($encoded,0,$encoded.Length)}finally{$stream.Dispose()}
}
Write-Output ('SYNTHETIC_RAW_ETL_PASS='+$passed.Count)
