using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace Hovborg.AIManager {
    public static class NotificationShortcut {
        [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
        private class ShellLink { }
        [StructLayout(LayoutKind.Sequential)]
        private struct PropertyKey {
            public Guid Format;
            public uint Id;
            public PropertyKey(uint id) { Format=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); Id=id; }
        }
        [StructLayout(LayoutKind.Explicit, Size=24)]
        private struct PropVariant {
            [FieldOffset(0)] public ushort Type;
            [FieldOffset(8)] public IntPtr Pointer;
        }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PropertyKey key);
            [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
            [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
            [PreserveSig] int Commit();
        }
        [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PropVariant value);
        [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        public static void SetProcessIdentity(string appId) {
            Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(appId));
        }

        public static void SetIdentity(string path, string appId, Guid activator) {
            object link=new ShellLink();
            try {
                var file=(IPersistFile)link;
                file.Load(path, 2);
                var store=(IPropertyStore)link;
                var appKey=new PropertyKey(5);
                var appValue=new PropVariant { Type=31, Pointer=Marshal.StringToCoTaskMemUni(appId) };
                try { Marshal.ThrowExceptionForHR(store.SetValue(ref appKey, ref appValue)); }
                finally { PropVariantClear(ref appValue); }
                var activatorKey=new PropertyKey(26);
                var activatorValue=new PropVariant { Type=72, Pointer=Marshal.AllocCoTaskMem(16) };
                try {
                    Marshal.StructureToPtr(activator, activatorValue.Pointer, false);
                    Marshal.ThrowExceptionForHR(store.SetValue(ref activatorKey, ref activatorValue));
                } finally { PropVariantClear(ref activatorValue); }
                Marshal.ThrowExceptionForHR(store.Commit());
                file.Save(path, true);
            } finally { Marshal.FinalReleaseComObject(link); }
        }

        public static string ReadAppId(string path) {
            object link=new ShellLink();
            try {
                ((IPersistFile)link).Load(path, 0);
                var key=new PropertyKey(5);
                PropVariant value;
                Marshal.ThrowExceptionForHR(((IPropertyStore)link).GetValue(ref key, out value));
                try { return value.Type==31 ? Marshal.PtrToStringUni(value.Pointer) : null; }
                finally { PropVariantClear(ref value); }
            } finally { Marshal.FinalReleaseComObject(link); }
        }
    }
}
