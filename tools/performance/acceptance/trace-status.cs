using System;
using System.Runtime.InteropServices;

// Windows x64 EVENT_TRACE_PROPERTIES, no provider enablement or global session
// operations. The caller supplies a new UUID session name it owns.
public static class HospitalTraceStatus {
    [StructLayout(LayoutKind.Sequential)] public struct Wnode {
        public uint BufferSize, ProviderId;
        public ulong HistoricalContext;
        public long TimeStamp;
        public Guid Guid;
        public uint ClientContext, Flags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Properties {
        public Wnode Wnode;
        public uint BufferSize, MinimumBuffers, MaximumBuffers, MaximumFileSize;
        public uint LogFileMode, FlushTimer, EnableFlags;
        public int AgeLimit;
        public uint NumberOfBuffers, FreeBuffers, EventsLost, BuffersWritten;
        public uint LogBuffersLost, RealTimeBuffersLost;
        public IntPtr LoggerThreadId;
        public uint LogFileNameOffset, LoggerNameOffset;
    }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="ControlTraceW")]
    private static extern uint ControlTrace(ulong handle, string name, IntPtr data, uint code);
    public static object Read(string ownedSession, bool stop) {
        int size = Marshal.SizeOf<Properties>(), bytes = size + 4096;
        if (IntPtr.Size != 8 || size != 120) throw new PlatformNotSupportedException("Expected Windows x64 EVENT_TRACE_PROPERTIES size 120.");
        IntPtr memory = Marshal.AllocHGlobal(bytes);
        try {
            for (int i=0; i<bytes; ++i) Marshal.WriteByte(memory,i,0);
            Properties data = new Properties();
            data.Wnode.BufferSize = (uint)bytes;
            data.LoggerNameOffset = (uint)size;
            Marshal.StructureToPtr(data,memory,false);
            uint result = ControlTrace(0,ownedSession,memory,stop ? 1u : 0u);
            data = Marshal.PtrToStructure<Properties>(memory);
            return new { code=result, events_lost=result==0 ? (long?)data.EventsLost : null,
                log_buffers_lost=result==0 ? (long?)data.LogBuffersLost : null,
                realtime_buffers_lost=result==0 ? (long?)data.RealTimeBuffersLost : null,
                action=stop ? "stop_owned_session" : "query_owned_session" };
        } finally { Marshal.FreeHGlobal(memory); }
    }
}

// Read only the already-owned process HANDLE. Private commit and working set
// have distinct fields; lifetime peaks are not relabelled as window peaks.
public static class HospitalProcessMemory {
    [StructLayout(LayoutKind.Sequential)] private struct Counters {
        public uint cb, PageFaultCount;
        public UIntPtr PeakWorkingSetSize, WorkingSetSize, QuotaPeakPagedPoolUsage,
            QuotaPagedPoolUsage, QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage,
            PagefileUsage, PeakPagefileUsage, PrivateUsage;
    }
    [DllImport("psapi.dll", SetLastError=true)]
    private static extern bool GetProcessMemoryInfo(IntPtr process, ref Counters counters, uint size);
    public static object Read(IntPtr ownedHandle) {
        Counters c=new Counters(); c.cb=(uint)Marshal.SizeOf<Counters>();
        if(!GetProcessMemoryInfo(ownedHandle,ref c,c.cb))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return new { working_set_bytes=c.WorkingSetSize.ToUInt64(),
            private_commit_bytes=c.PrivateUsage.ToUInt64(),
            lifetime_peak_working_set_bytes=c.PeakWorkingSetSize.ToUInt64(),
            lifetime_peak_private_commit_bytes=c.PeakPagefileUsage.ToUInt64() };
    }
}
