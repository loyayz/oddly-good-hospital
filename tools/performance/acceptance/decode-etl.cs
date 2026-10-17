using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;

// Offline ETL consumer only. No session creation, provider enablement or live
// consumer mode exists here. EVENT_RECORD timestamps remain in the ETL clock.
public static class HospitalRawEtlReader {
    const uint EventRecordMode=0x10000000, RawTimestampMode=0x00001000;
    const ushort Header32=0x20, Header64=0x40;
    static readonly Guid Dxg=new Guid("802ec45a-1e99-4b83-9920-87c98277ba9d");

    [StructLayout(LayoutKind.Explicit,Size=280)] struct TraceHeader {
        [FieldOffset(0)] public uint BufferSize;
        [FieldOffset(4)] public uint Version;
        [FieldOffset(8)] public uint ProviderVersion;
        [FieldOffset(12)] public uint NumberOfProcessors;
        [FieldOffset(16)] public long EndTime;
        [FieldOffset(24)] public uint TimerResolution;
        [FieldOffset(28)] public uint MaximumFileSize;
        [FieldOffset(32)] public uint LogFileMode;
        [FieldOffset(36)] public uint BuffersWritten;
        [FieldOffset(40)] public uint StartBuffers;
        [FieldOffset(44)] public uint PointerSize;
        [FieldOffset(48)] public uint EventsLost;
        [FieldOffset(52)] public uint CpuSpeedInMHz;
        [FieldOffset(56)] public IntPtr LoggerName;
        [FieldOffset(64)] public IntPtr LogFileName;
        // TIME_ZONE_INFORMATION occupies the reserved bytes 72..243.
        [FieldOffset(248)] public long BootTime;
        [FieldOffset(256)] public long PerfFreq;
        [FieldOffset(264)] public long StartTime;
        [FieldOffset(272)] public uint ReservedFlags;
        [FieldOffset(276)] public uint BuffersLost;
    }
    [StructLayout(LayoutKind.Explicit,Size=448)] struct Logfile {
        [FieldOffset(0)] public IntPtr LogFileName;
        [FieldOffset(8)] public IntPtr LoggerName;
        [FieldOffset(16)] public long CurrentTime;
        [FieldOffset(24)] public uint BuffersRead;
        [FieldOffset(28)] public uint ProcessTraceMode;
        // EVENT_TRACE occupies the reserved bytes 32..119.
        [FieldOffset(120)] public TraceHeader Header;
        [FieldOffset(400)] public IntPtr BufferCallback;
        [FieldOffset(408)] public uint BufferSize;
        [FieldOffset(412)] public uint Filled;
        [FieldOffset(416)] public uint EventsLostUnused;
        [FieldOffset(424)] public IntPtr EventRecordCallback;
        [FieldOffset(432)] public uint IsKernelTrace;
        [FieldOffset(440)] public IntPtr Context;
    }
    [StructLayout(LayoutKind.Sequential)] struct Descriptor {
        public ushort Id;
        public byte Version,Channel,Level,Opcode;
        public ushort Task;
        public ulong Keyword;
    }
    [StructLayout(LayoutKind.Explicit,Size=80)] struct EventHeader {
        [FieldOffset(0)] public ushort Size;
        [FieldOffset(2)] public ushort HeaderType;
        [FieldOffset(4)] public ushort Flags;
        [FieldOffset(6)] public ushort EventProperty;
        [FieldOffset(8)] public uint ThreadId;
        [FieldOffset(12)] public uint ProcessId;
        [FieldOffset(16)] public long TimeStamp;
        [FieldOffset(24)] public Guid ProviderId;
        [FieldOffset(40)] public Descriptor Descriptor;
        [FieldOffset(56)] public ulong ProcessorTime;
        [FieldOffset(64)] public Guid ActivityId;
    }
    [StructLayout(LayoutKind.Explicit,Size=112)] struct Record {
        [FieldOffset(0)] public EventHeader Header;
        [FieldOffset(80)] public uint BufferContext;
        [FieldOffset(84)] public ushort ExtendedDataCount;
        [FieldOffset(86)] public ushort UserDataLength;
        [FieldOffset(88)] public IntPtr ExtendedData;
        [FieldOffset(96)] public IntPtr UserData;
        [FieldOffset(104)] public IntPtr UserContext;
    }
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void EventCallback(IntPtr record);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate uint BufferCallback(IntPtr logfile);
    [DllImport("advapi32.dll",EntryPoint="OpenTraceW",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern ulong OpenTrace(ref Logfile logfile);
    [DllImport("advapi32.dll",SetLastError=true)]
    static extern uint ProcessTrace([In] ulong[] handles,uint count,IntPtr start,IntPtr end);
    [DllImport("advapi32.dll",SetLastError=true)] static extern uint CloseTrace(ulong handle);

    public sealed class EventSchema {
        public int Id,Version,Task,Opcode;
        public string TaskName,Template,Error;
        internal readonly List<Field> Fields=new List<Field>();
        public EventSchema(int id,int version,int task,int opcode,string taskName,string template) {
            Id=id;Version=version;Task=task;Opcode=opcode;TaskName=taskName;Template=template;
            try {
                if(String.IsNullOrEmpty(template) || template.Length>2*1024*1024) throw new InvalidDataException("missing or excessive template");
                XmlReaderSettings settings=new XmlReaderSettings{DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=2*1024*1024};
                XmlDocument xml=new XmlDocument{XmlResolver=null};
                using(XmlReader reader=XmlReader.Create(new StringReader(template),settings)) xml.Load(reader);
                if(xml.DocumentElement==null || xml.DocumentElement.LocalName!="template") throw new InvalidDataException("template root missing");
                HashSet<string> names=new HashSet<string>(StringComparer.Ordinal);
                foreach(XmlNode node in xml.DocumentElement.ChildNodes) {
                    XmlElement element=node as XmlElement;
                    if(element==null) continue;
                    if(element.LocalName!="data") throw new InvalidDataException("unsupported struct/template node: "+element.LocalName);
                    string name=element.GetAttribute("name"),type=element.GetAttribute("inType"),count=element.GetAttribute("count"),length=element.GetAttribute("length");
                    if(name.Length==0 || !names.Add(name)) throw new InvalidDataException("missing or duplicate field name");
                    string countFrom=null;
                    if(count.Length>0 && count!="1") {
                        // DpiReportAdapter.ConfigSpace is packed UInt8[count],
                        // bounded by an already decoded UInt32 field. Other
                        // dynamic layouts remain unsupported.
                        Field source=Fields.Find(f=>f.Name==count && f.Type=="win:UInt32" && f.CountFrom==null);
                        if(type!="win:UInt8" || source==null || length.Length>0) throw new InvalidDataException("unsupported array/count: "+name);
                        countFrom=count;
                    }
                    int binaryLength=-1;
                    if(length.Length>0 && (type!="win:Binary" || !Int32.TryParse(length,NumberStyles.None,CultureInfo.InvariantCulture,out binaryLength) || binaryLength<0 || binaryLength>65535))
                        throw new InvalidDataException("unsupported dynamic/fixed length: "+name);
                    if(!Supported(type) || (type=="win:Binary" && binaryLength<0)) throw new InvalidDataException("unsupported type: "+type);
                    Fields.Add(new Field{Name=name,Type=type,BinaryLength=binaryLength,CountFrom=countFrom});
                }
            } catch(Exception error) { Error=error.Message; }
        }
    }
    internal sealed class Field { internal string Name,Type,CountFrom; internal int BinaryLength; }
    public sealed class Decoded {
        public string Status="incomplete",Error;
        public int Consumed,PointerSize;
        public Dictionary<string,object> Data=new Dictionary<string,object>(StringComparer.Ordinal);
        public List<object> Fields=new List<object>();
    }
    public sealed class Result {
        public string Status="incomplete",Error;
        public bool RawFileReadComplete,RawQpcValid;
        public long Records,ProviderRecords,Emitted,FilteredOut,Decoded,Incomplete;
        public long? FirstRawTimestamp,LastRawTimestamp;
        public uint? OpenError,ProcessStatus,CloseStatus;
        public uint BuffersRead;
        public Dictionary<string,object> TraceHeader;
        public Dictionary<string,long> DecodeFailures=new Dictionary<string,long>(StringComparer.Ordinal);
        public Dictionary<string,long> EmittedEventCounts=new Dictionary<string,long>(StringComparer.Ordinal);
    }

    static bool Supported(string type) {
        switch(type) {
            case "win:UInt8": case "win:Int8": case "win:UInt16": case "win:Int16":
            case "win:UInt32": case "win:Int32": case "win:UInt64": case "win:Int64":
            case "win:HexInt32": case "win:HexInt64": case "win:Pointer": case "win:Boolean":
            case "win:Float": case "win:Double": case "win:GUID": case "win:UnicodeString": case "win:Binary": return true;
            default:return false;
        }
    }
    static void Require(byte[] data,int offset,int count) {
        if(count<0 || offset<0 || count>data.Length-offset) throw new InvalidDataException("payload truncated at offset "+offset);
    }
    static string Scalar(Field f,byte[] bytes,ref int offset,int pointers) {
        int size;
        switch(f.Type) {
            case "win:UInt8":case "win:Int8":size=1;break;
            case "win:UInt16":case "win:Int16":size=2;break;
            case "win:UInt32":case "win:Int32":case "win:HexInt32":case "win:Boolean":case "win:Float":size=4;break;
            case "win:UInt64":case "win:Int64":case "win:HexInt64":case "win:Double":size=8;break;
            case "win:Pointer":size=pointers;break;
            case "win:GUID":size=16;break;
            case "win:Binary":size=f.BinaryLength;break;
            case "win:UnicodeString": {
                int end=offset;
                while(true) {Require(bytes,end,2);if(bytes[end]==0 && bytes[end+1]==0) break;end+=2;}
                string text=new UnicodeEncoding(false,false,true).GetString(bytes,offset,end-offset);
                offset=end+2;return text;
            }
            default:throw new InvalidDataException("unsupported type "+f.Type);
        }
        Require(bytes,offset,size);
        int at=offset;offset+=size;
        switch(f.Type) {
            case "win:UInt8":return bytes[at].ToString(CultureInfo.InvariantCulture);
            case "win:Int8":return unchecked((sbyte)bytes[at]).ToString(CultureInfo.InvariantCulture);
            case "win:UInt16":return BitConverter.ToUInt16(bytes,at).ToString(CultureInfo.InvariantCulture);
            case "win:Int16":return BitConverter.ToInt16(bytes,at).ToString(CultureInfo.InvariantCulture);
            case "win:UInt32":return BitConverter.ToUInt32(bytes,at).ToString(CultureInfo.InvariantCulture);
            case "win:Int32":return BitConverter.ToInt32(bytes,at).ToString(CultureInfo.InvariantCulture);
            case "win:UInt64":return BitConverter.ToUInt64(bytes,at).ToString(CultureInfo.InvariantCulture);
            case "win:Int64":return BitConverter.ToInt64(bytes,at).ToString(CultureInfo.InvariantCulture);
            case "win:HexInt32":return "0x"+BitConverter.ToUInt32(bytes,at).ToString("x8",CultureInfo.InvariantCulture);
            case "win:HexInt64":return "0x"+BitConverter.ToUInt64(bytes,at).ToString("x16",CultureInfo.InvariantCulture);
            case "win:Pointer":return "0x"+(size==4?(ulong)BitConverter.ToUInt32(bytes,at):BitConverter.ToUInt64(bytes,at)).ToString(size==4?"x8":"x16",CultureInfo.InvariantCulture);
            case "win:Boolean":return BitConverter.ToUInt32(bytes,at)==0?"false":"true";
            case "win:Float":return BitConverter.ToSingle(bytes,at).ToString("R",CultureInfo.InvariantCulture);
            case "win:Double":return BitConverter.ToDouble(bytes,at).ToString("R",CultureInfo.InvariantCulture);
            case "win:GUID": {byte[] raw=new byte[16];Array.Copy(bytes,at,raw,0,16);return new Guid(raw).ToString("D");}
            case "win:Binary":return Convert.ToBase64String(bytes,at,size);
            default:throw new InvalidDataException("unsupported type "+f.Type);
        }
    }
    public static Decoded DecodePayload(EventSchema schema,byte[] payload,ushort headerFlags,int tracePointerSize) {
        Decoded result=new Decoded();
        try {
            if(!BitConverter.IsLittleEndian) throw new PlatformNotSupportedException("little-endian payload reader required");
            if(schema==null) throw new InvalidDataException("event schema unavailable");
            if(schema.Error!=null) throw new InvalidDataException(schema.Error);
            bool bit32=(headerFlags&Header32)!=0,bit64=(headerFlags&Header64)!=0;
            if(bit32 && bit64) throw new InvalidDataException("conflicting pointer-width header flags");
            int pointers=bit32?4:bit64?8:tracePointerSize;
            if(pointers!=4 && pointers!=8) throw new InvalidDataException("unknown payload pointer width");
            result.PointerSize=pointers;
            int offset=0;
            foreach(Field field in schema.Fields) {
                int begin=offset;
                string value;
                Dictionary<string,object> detail=new Dictionary<string,object>{{"name",field.Name},{"in_type",field.Type},{"offset",begin}};
                if(field.CountFrom!=null) {
                    object source;uint count;
                    if(!result.Data.TryGetValue(field.CountFrom,out source) || !UInt32.TryParse((string)source,NumberStyles.None,CultureInfo.InvariantCulture,out count) || count>65535)
                        throw new InvalidDataException("invalid bounded UInt8 array count: "+field.Name);
                    Require(payload,offset,(int)count);
                    value=Convert.ToBase64String(payload,offset,(int)count);offset+=(int)count;
                    detail.Add("count_from",field.CountFrom);detail.Add("count",count);detail.Add("encoding","base64");
                } else value=Scalar(field,payload,ref offset,pointers);
                detail.Add("value",value);detail.Add("bytes",offset-begin);
                result.Fields.Add(detail);
                result.Data.Add(field.Name,value);
            }
            result.Consumed=offset;
            if(offset!=payload.Length) throw new InvalidDataException("payload trailing bytes: "+(payload.Length-offset));
            result.Status="decoded";
        } catch(Exception error) {
            result.Error=error.Message;
            // Prefix fields remain diagnostic only. A ledger consuming the old
            // data map must never silently accept a partial layout as success.
            result.Data.Clear();
        }
        return result;
    }

    static Dictionary<string,object> HeaderData(TraceHeader header) {
        return new Dictionary<string,object>{
            {"buffer_size",header.BufferSize},{"version",header.Version},{"provider_version",header.ProviderVersion},
            {"number_of_processors",header.NumberOfProcessors},{"end_time_filetime",header.EndTime},
            {"start_time_filetime",header.StartTime},{"boot_time_filetime",header.BootTime},
            {"timer_resolution_100ns",header.TimerResolution},{"log_file_mode",header.LogFileMode},
            {"buffers_written",header.BuffersWritten},{"pointer_size",header.PointerSize},
            {"events_lost",header.EventsLost},{"buffers_lost",header.BuffersLost},
            {"perf_frequency",header.PerfFreq},{"reserved_flags_clock_type",header.ReservedFlags}
        };
    }
    static string Quote(string text) {
        StringBuilder output=new StringBuilder("\"");
        foreach(char c in text) {
            switch(c) {
                case '"':output.Append("\\\"");break;
                case '\\':output.Append("\\\\");break;
                case '\n':output.Append("\\n");break;
                case '\r':output.Append("\\r");break;
                case '\t':output.Append("\\t");break;
                default:
                    if(c<32 || Char.IsSurrogate(c)) output.Append("\\u").Append(((int)c).ToString("x4",CultureInfo.InvariantCulture));
                    else output.Append(c);
                    break;
            }
        }
        return output.Append('"').ToString();
    }
    public static string Json(object value) {
        if(value==null) return "null";
        string text=value as string;if(text!=null) return Quote(text);
        if(value is bool) return (bool)value?"true":"false";
        IDictionary map=value as IDictionary;
        if(map!=null) {List<string> items=new List<string>();foreach(DictionaryEntry pair in map) items.Add(Quote((string)pair.Key)+":"+Json(pair.Value));return "{"+String.Join(",",items)+"}";}
        IEnumerable list=value as IEnumerable;
        if(list!=null) {List<string> items=new List<string>();foreach(object item in list) items.Add(Json(item));return "["+String.Join(",",items)+"]";}
        if(value is byte || value is sbyte || value is short || value is ushort || value is int || value is uint || value is long || value is ulong || value is decimal)
            return ((IFormattable)value).ToString(null,CultureInfo.InvariantCulture);
        throw new InvalidDataException("unsupported JSON metadata value type: "+value.GetType().FullName);
    }
    public static Dictionary<string,int> Layout() {
        Dictionary<string,int> values=new Dictionary<string,int>{
            {"pointer_size",IntPtr.Size},{"descriptor_size",Marshal.SizeOf<Descriptor>()},
            {"event_header_size",Marshal.SizeOf<EventHeader>()},{"event_record_size",Marshal.SizeOf<Record>()},
            {"trace_header_size",Marshal.SizeOf<TraceHeader>()},{"logfile_size",Marshal.SizeOf<Logfile>()},
            {"event_record_userdata",(int)Marshal.OffsetOf<Record>("UserData")},
            {"event_header_timestamp",(int)Marshal.OffsetOf<EventHeader>("TimeStamp")},
            {"logfile_header",(int)Marshal.OffsetOf<Logfile>("Header")},
            {"logfile_callback",(int)Marshal.OffsetOf<Logfile>("EventRecordCallback")},
            {"trace_header_perffreq",(int)Marshal.OffsetOf<TraceHeader>("PerfFreq")}
        };
        if(values["pointer_size"]!=8 || values["descriptor_size"]!=16 || values["event_header_size"]!=80 || values["event_record_size"]!=112 || values["trace_header_size"]!=280 || values["logfile_size"]!=448 || values["event_record_userdata"]!=96 || values["event_header_timestamp"]!=16 || values["logfile_header"]!=120 || values["logfile_callback"]!=424 || values["trace_header_perffreq"]!=256)
            throw new PlatformNotSupportedException("Unexpected Windows x64 ETW ABI layout.");
        return values;
    }

    sealed class Reader {
        readonly StreamWriter output;
        readonly Dictionary<string,EventSchema> schemas;
        readonly HashSet<int> eventIds;
        internal readonly Result Result=new Result();
        internal TraceHeader Header;
        internal readonly EventCallback Event;
        internal readonly BufferCallback Buffer;
        internal Reader(StreamWriter writer,EventSchema[] definitions,int[] selectedIds=null) {
            output=writer;schemas=new Dictionary<string,EventSchema>(StringComparer.Ordinal);
            if(selectedIds!=null && selectedIds.Length>0) {
                eventIds=new HashSet<int>(selectedIds);
                foreach(int id in eventIds) if(id<0 || id>65535) throw new ArgumentOutOfRangeException("selectedIds");
            }
            foreach(EventSchema schema in definitions) {
                string key=schema.Id+":"+schema.Version;
                if(schemas.ContainsKey(key)) throw new InvalidDataException("duplicate event schema: "+key);
                schemas.Add(key,schema);
            }
            Event=OnEvent;Buffer=OnBuffer;
        }
        uint OnBuffer(IntPtr pointer) {
            try {Logfile log=Marshal.PtrToStructure<Logfile>(pointer);Result.BuffersRead=log.BuffersRead;Header=log.Header;}
            catch(Exception error) {Result.Error="buffer callback: "+error.Message;}
            return Result.Error==null?1u:0u;
        }
        void OnEvent(IntPtr pointer) {
            if(Result.Error!=null) return;
            try {
                Record record=Marshal.PtrToStructure<Record>(pointer);
                Result.Records++;
                if(record.Header.ProviderId!=Dxg) return;
                // Keep the same ordinal as a full decode, so supplemental
                // records can be joined without a second 3GB JSON expansion.
                long sequence=++Result.ProviderRecords;
                if(!Result.FirstRawTimestamp.HasValue) Result.FirstRawTimestamp=record.Header.TimeStamp;
                Result.LastRawTimestamp=record.Header.TimeStamp;
                if(eventIds!=null && !eventIds.Contains(record.Header.Descriptor.Id)) {Result.FilteredOut++;return;}
                Result.Emitted++;
                byte[] payload=new byte[record.UserDataLength];
                if(payload.Length>0) {
                    if(record.UserData==IntPtr.Zero) throw new InvalidDataException("nonempty payload has null native address");
                    Marshal.Copy(record.UserData,payload,0,payload.Length);
                }
                Descriptor d=record.Header.Descriptor;
                string eventKey=d.Id+":"+d.Version;long eventCount;
                Result.EmittedEventCounts.TryGetValue(eventKey,out eventCount);Result.EmittedEventCounts[eventKey]=eventCount+1;
                EventSchema schema;
                schemas.TryGetValue(d.Id+":"+d.Version,out schema);
                Decoded decoded;
                if(record.Header.Size<80) decoded=new Decoded{Error="EVENT_HEADER smaller than 80"};
                else if(schema!=null && ((schema.Task>=0 && schema.Task!=d.Task) || (schema.Opcode>=0 && schema.Opcode!=d.Opcode))) decoded=new Decoded{Error="task/opcode mismatch against fixed schema"};
                else decoded=DecodePayload(schema,payload,record.Header.Flags,(int)Header.PointerSize);
                bool qpc=Header.ReservedFlags==1 && Header.PerfFreq>0;
                Dictionary<string,object> row=new Dictionary<string,object>{
                    {"kind","dxgkrnl_event"},{"sequence",sequence},{"provider","Microsoft-Windows-DxgKrnl"},{"provider_guid",record.Header.ProviderId.ToString("D")},
                    {"event_id",d.Id},{"version",d.Version},{"channel",d.Channel},{"level",d.Level},{"opcode_value",d.Opcode},{"task_value",d.Task},{"keyword","0x"+d.Keyword.ToString("x16",CultureInfo.InvariantCulture)},
                    {"task",schema==null?null:schema.TaskName},{"opcode",d.Opcode==1?"Start":d.Opcode==2?"Stop":d.Opcode==3?"DC_Start":d.Opcode==4?"DC_Stop":null},
                    {"header_pid",record.Header.ProcessId},{"header_tid",record.Header.ThreadId},{"header_flags",record.Header.Flags},{"header_type",record.Header.HeaderType},{"event_property",record.Header.EventProperty},
                    {"activity_id",record.Header.ActivityId.ToString("D")},{"buffer_context",record.BufferContext},{"extended_data_count",record.ExtendedDataCount},
                    {"raw_timestamp",record.Header.TimeStamp},{"qpc_ticks",qpc?(object)record.Header.TimeStamp:null},
                    {"qpc_frequency",qpc?(object)Header.PerfFreq:null},{"clock_domain",qpc?"windows_qpc":"raw_etw_clock_"+Header.ReservedFlags},
                    {"trace_perf_frequency",Header.PerfFreq},{"trace_clock_type",Header.ReservedFlags},{"system_time",null},
                    {"user_data_length",payload.Length},{"user_data_base64",Convert.ToBase64String(payload)},
                    {"decode_status",decoded.Status},{"decode_error",decoded.Error},{"pointer_size",decoded.PointerSize},{"decoded_bytes",decoded.Consumed},
                    {"data",decoded.Data},{"data_fields",decoded.Fields}
                };
                if(decoded.Status=="decoded") Result.Decoded++;
                else {Result.Incomplete++;string reason=decoded.Error??"unknown decode error";long count;Result.DecodeFailures.TryGetValue(reason,out count);Result.DecodeFailures[reason]=count+1;}
                output.WriteLine(Json(row));
            } catch(Exception error) {Result.Error="event callback: "+error.Message;}
        }
    }
    public static Result Read(string etl,string outputPath,EventSchema[] schemas) {
        return Read(etl,outputPath,schemas,null);
    }
    public static Result Read(string etl,string outputPath,EventSchema[] schemas,int[] eventIds) {
        Layout();
        if(!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) throw new PlatformNotSupportedException("Windows ETL reader required");
        string input=Path.GetFullPath(etl),destination=Path.GetFullPath(outputPath);
        if(String.Equals(input,destination,StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("ETL and output must differ");
        if(!File.Exists(input)) throw new FileNotFoundException("ETL missing",input);
        using(FileStream file=new FileStream(destination,FileMode.CreateNew,FileAccess.Write,FileShare.Read))
        using(StreamWriter writer=new StreamWriter(file,new UTF8Encoding(false,true),65536)) {
            Reader reader=new Reader(writer,schemas,eventIds);Logfile log=new Logfile();
            IntPtr path=Marshal.StringToHGlobalUni(input);ulong handle=UInt64.MaxValue;
            try {
                log.LogFileName=path;log.ProcessTraceMode=EventRecordMode|RawTimestampMode;
                log.EventRecordCallback=Marshal.GetFunctionPointerForDelegate(reader.Event);
                log.BufferCallback=Marshal.GetFunctionPointerForDelegate(reader.Buffer);
                handle=OpenTrace(ref log);
                if(handle==UInt64.MaxValue) {
                    reader.Result.OpenError=(uint)Marshal.GetLastWin32Error();
                    throw new Win32Exception((int)reader.Result.OpenError.Value,"OpenTraceW failed");
                }
                reader.Header=log.Header;
                reader.Result.ProcessStatus=ProcessTrace(new[]{handle},1,IntPtr.Zero,IntPtr.Zero);
                if(reader.Result.ProcessStatus!=0 && reader.Result.Error==null) reader.Result.Error="ProcessTrace status "+reader.Result.ProcessStatus;
                reader.Result.RawFileReadComplete=reader.Result.ProcessStatus==0 && reader.Result.Error==null;
            } catch(Exception error) {if(reader.Result.Error==null) reader.Result.Error=error.Message;}
            finally {
                if(handle!=UInt64.MaxValue) reader.Result.CloseStatus=CloseTrace(handle);
                Marshal.FreeHGlobal(path);GC.KeepAlive(reader.Event);GC.KeepAlive(reader.Buffer);
            }
            writer.Flush();
            reader.Result.TraceHeader=HeaderData(reader.Header);
            reader.Result.RawQpcValid=reader.Header.ReservedFlags==1 && reader.Header.PerfFreq>0;
            bool good=reader.Result.RawFileReadComplete && reader.Result.CloseStatus==0 && reader.Result.RawQpcValid && reader.Result.Emitted>0 && reader.Result.Incomplete==0 && reader.Header.EndTime!=0 && reader.Header.EventsLost==0 && reader.Header.BuffersLost==0;
            reader.Result.Status=good?"decoded":"incomplete";
            return reader.Result;
        }
    }

    // Synthetic callback/layout check. This never opens a trace or invokes any
    // P/Invoke entry point; it marshals only memory allocated by this method.
    public static string SyntheticRecordJson(EventSchema schema,byte[] payload,ushort flags,long timestamp,uint clockType,int tracePointerSize) {
        Layout();
        if(payload.Length>65535) throw new ArgumentException("synthetic payload exceeds EVENT_RECORD length");
        using(MemoryStream bytes=new MemoryStream())
        using(StreamWriter writer=new StreamWriter(bytes,new UTF8Encoding(false,true),1024,true)) {
            Reader reader=new Reader(writer,new[]{schema});
            reader.Header=new TraceHeader{PointerSize=(uint)tracePointerSize,ReservedFlags=clockType,PerfFreq=10000000};
            IntPtr body=Marshal.AllocHGlobal(Math.Max(1,payload.Length)),native=Marshal.AllocHGlobal(112);
            try {
                if(payload.Length>0) Marshal.Copy(payload,0,body,payload.Length);
                Record record=new Record{Header=new EventHeader{Size=80,Flags=flags,ProviderId=Dxg,ProcessId=4242,ThreadId=7,TimeStamp=timestamp,
                    Descriptor=new Descriptor{Id=(ushort)schema.Id,Version=(byte)schema.Version,Task=(ushort)Math.Max(0,schema.Task),Opcode=(byte)Math.Max(0,schema.Opcode)}},
                    UserDataLength=(ushort)payload.Length,UserData=body};
                Marshal.StructureToPtr(record,native,false);
                reader.Event(native);writer.Flush();
                if(reader.Result.Error!=null) throw new InvalidDataException(reader.Result.Error);
                return Encoding.UTF8.GetString(bytes.ToArray());
            } finally {Marshal.FreeHGlobal(native);Marshal.FreeHGlobal(body);}
        }
    }
}
