using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Runtime.InteropServices;

// Real OS input only to the current foreground owned game. Never activates a
// different window, sends window messages or fabricates Godot input callbacks.
public static class HospitalInput {
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct Mouse { public int X,Y; public uint Data,Flags,Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct Key { public ushort Vk,Scan; public uint Flags,Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] private struct Payload {
        [FieldOffset(0)] public Mouse Mouse;
        [FieldOffset(0)] public Key Key;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public Payload Data; }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool GetClientRect(IntPtr window,out Rect rect);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool ScreenToClient(IntPtr window,ref Point point);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool ClientToScreen(IntPtr window,ref Point point);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll",SetLastError=true)] private static extern uint SendInput(uint count,Input[] inputs,int size);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    private static IntPtr Owned(int pid) {
        IntPtr window=GetForegroundWindow(); uint actual;
        GetWindowThreadProcessId(window,out actual);
        if(window==IntPtr.Zero || actual!=(uint)pid) throw new InvalidOperationException("Owned game is not foreground; no input sent.");
        return window;
    }
    private static Input Keyboard(ushort key,ushort scan,uint flags) {
        Input input=new Input(); input.Type=1; input.Data.Key=new Key{Vk=key,Scan=scan,Flags=flags}; return input;
    }
    private static void Send(int pid,Input[] events) {
        Owned(pid);
        int size=Marshal.SizeOf<Input>();
        if(IntPtr.Size!=8 || size!=40) throw new PlatformNotSupportedException("Expected Windows x64 INPUT size 40.");
        if(SendInput((uint)events.Length,events,size)!=(uint)events.Length)
            throw new Win32Exception(Marshal.GetLastWin32Error(),"SendInput did not deliver the complete batch.");
    }
    public static void Click(int pid,int physicalX,int physicalY) {
        IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            IntPtr window=Owned(pid); Rect rect; Point p=new Point{X=physicalX,Y=physicalY};
            if(!GetClientRect(window,out rect) || !ScreenToClient(window,ref p)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if(p.X<rect.Left || p.X>=rect.Right || p.Y<rect.Top || p.Y>=rect.Bottom)
                throw new InvalidOperationException("Input point is outside the owned game's physical client rectangle.");
            if(!SetCursorPos(physicalX,physicalY)) throw new Win32Exception(Marshal.GetLastWin32Error());
            Input down=new Input(),up=new Input(); down.Data.Mouse.Flags=2; up.Data.Mouse.Flags=4;
            Send(pid,new[]{down,up});
        } finally { if(previous!=IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static int[] ClickClient(int pid,int clientX,int clientY) {
        IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            IntPtr window=Owned(pid); Rect rect; Point point=new Point{X=clientX,Y=clientY};
            if(!GetClientRect(window,out rect)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if(point.X<rect.Left || point.X>=rect.Right || point.Y<rect.Top || point.Y>=rect.Bottom)
                throw new InvalidOperationException("Input point is outside the owned game's physical client rectangle.");
            if(!ClientToScreen(window,ref point)) throw new Win32Exception(Marshal.GetLastWin32Error());
            Click(pid,point.X,point.Y);
            return new[]{point.X,point.Y};
        } finally { if(previous!=IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static void ReplaceText(int pid,string text) {
        if(text==null || text.Length>128) throw new ArgumentException("Expected bounded input text.");
        Send(pid,new[]{Keyboard(0x11,0,0),Keyboard(0x41,0,0),Keyboard(0x41,0,2),Keyboard(0x11,0,2)});
        foreach(char c in text) Send(pid,new[]{Keyboard(0,c,4),Keyboard(0,c,6)});
        Send(pid,new[]{Keyboard(0x0d,0,0),Keyboard(0x0d,0,2)});
    }
}
