#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Etl,[Parameter(Mandatory)][string]$Output,[switch]$IncludeXml)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Decoded evidence already exists.'}
$writer=[IO.StreamWriter]::new([IO.Path]::GetFullPath($Output),$false,[Text.UTF8Encoding]::new($false))
$count=0
try {
    Get-WinEvent -Path $Etl -Oldest -ErrorAction Stop | ForEach-Object {
        if($_.ProviderName -eq 'Microsoft-Windows-DxgKrnl'){
            $rawXml=$_.ToXml();[xml]$xml=$rawXml;$data=[ordered]@{};$fields=@();$index=0
            foreach($entry in $xml.Event.EventData.Data){
                $name=[string]$entry.Name;if(-not $name){$name='field_'+$index}
                $value=[string]$entry.'#text';$fields+=@{name=$name;value=$value;index=$index}
                if(-not $data.Contains($name)){$data[$name]=$value}
                $index++
            }
            # SystemTime is ETW's converted wall time, NOT raw QPC. Preserve it
            # without pretending a precise QPC mapping or allocation lifetime.
            $row=@{provider=$_.ProviderName;event_id=$_.Id;version=$_.Version;task=$_.TaskDisplayName;opcode=$_.OpcodeDisplayName;opcode_value=$_.Opcode;header_pid=$_.ProcessId;record_id=$_.RecordId;system_time=[string]$xml.Event.System.TimeCreated.SystemTime;qpc_ticks=$null;clock_domain='etw_converted_system_time';data=$data;data_fields=$fields}
            if($IncludeXml -or -not $fields.Count){$row.raw_xml=$rawXml}
            $writer.WriteLine(($row | ConvertTo-Json -Depth 8 -Compress));$count++
        }
    }
} finally {$writer.Dispose()}
Write-Output "DECODED_EVENTS=$count"
@{schema_version=1;events=$count;etl_path=[IO.Path]::GetFullPath($Etl);etl_sha256=(Get-FileHash -LiteralPath $Etl -Algorithm SHA256).Hash.ToLowerInvariant();output=[IO.Path]::GetFullPath($Output);raw_qpc_available=$false;time_basis='Get-WinEvent converted SystemTime; no fabricated QPC join'}|ConvertTo-Json|Set-Content -LiteralPath ($Output+'.meta.json') -Encoding utf8NoBOM
