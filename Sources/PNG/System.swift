//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Android)
    import Android
#elseif canImport(Musl)
    import Musl
#elseif os(Windows)
    #warning("Windows in not oficially supported and is untested platform (please open an issue at https://github.com/tayloraswift/swift-png/issues)")
    import ucrt
#else
    #warning("unsupported or untested platform (please open an issue at https://github.com/tayloraswift/swift-png/issues)")
#endif

#if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl) || os(Windows)

/// A namespace for platform-dependent functionality.
///
/// These APIs are only available on MacOS and Linux. The rest of the
/// framework is pure Swift and supports all Swift platforms.
public
enum System
{
    /// A namespace for file IO functionality.
    public
    enum File
    {
        #if os(Android)
        typealias Descriptor = OpaquePointer
        #else
        typealias Descriptor = UnsafeMutablePointer<FILE>
        #endif

        /// A type for reading data from files on disk.
        public
        struct Source
        {
            private
            let descriptor:Descriptor
        }

        /// A type for writing data to files on disk.
        public
        struct Destination
        {
            private
            let descriptor:Descriptor
        }
    }
}
extension System.File.Source
{
    /// Calls a closure with an interface for reading from the specified file.
    ///
    /// This method automatically closes the file when its closure argument returns.
    /// -   Parameter path:
    ///     The path to the file to open.
    /// -   Parameter body:
    ///     A closure with a ``Source`` parameter from which data in
    ///     the specified file can be read. This interface is only valid
    ///     for the duration of the method’s execution. The closure is
    ///     only executed if the specified file could be successfully
    ///     opened, otherwise this method will return `nil`. If `body` has a
    ///     return value and the specified file could be opened, this method
    ///     returns the return value of the closure.
    /// -   Returns:
    ///     The return value of the closure argument, or `nil` if the specified
    ///     file could not be opened.
    public static
    func open<R>(path:String, _ body:(inout Self) throws -> R)
        rethrows -> R?
    {
        guard let descriptor:System.File.Descriptor = fopen(path, "rb")
        else
        {
            return nil
        }

        var file:Self = .init(descriptor: descriptor)
        defer
        {
            fclose(file.descriptor)
        }

        return try body(&file)
    }

    /// Reads the specified number of bytes from this file interface.
    ///
    /// This method only returns an array if the exact number of bytes
    /// specified could be read. This method advances the file pointer.
    /// -   Parameter capacity:
    ///     The number of bytes to read.
    /// -   Returns:
    ///     An array containing the read data, or `nil` if the specified
    ///     number of bytes could not be read.
    public
    func read(count capacity:Int) -> [UInt8]?
    {
        let buffer:[UInt8] = .init(unsafeUninitializedCapacity: capacity)
        {
            (buffer:inout UnsafeMutableBufferPointer<UInt8>, count:inout Int) in

            #if os(Android)
            let baseAddress = buffer.baseAddress!
            #else
            let baseAddress = buffer.baseAddress
            #endif
            count = fread(baseAddress, MemoryLayout<UInt8>.stride,
                capacity, self.descriptor)
        }

        guard buffer.count == capacity
        else
        {
            return nil
        }

        return buffer
    }
    /// The size of the file, in bytes, or `nil` if the file is not a regular
    /// file or a link to a file.
    ///
    /// This property queries the file size using `stat`.
    public
    var count:Int?
    {
        let descriptor:Int32 = fileno(self.descriptor)
        guard descriptor != -1
        else
        {
            return nil
        }

        guard let status:stat =
        ({
            var status:stat = .init()
            guard fstat(descriptor, &status) == 0
            else
            {
                return nil
            }
            return status
        }())
        else
        {
            return nil
        }

        #if os(Windows)
        switch Int32.init(status.st_mode) & S_IFMT
        {
        case S_IFREG:
            break
        default:
            return nil
        }
        #else
        switch status.st_mode & S_IFMT
        {
        case S_IFREG, S_IFLNK:
            break
        default:
            return nil
        }
        #endif

        return Int.init(status.st_size)
    }
}
extension System.File.Destination
{
    /// Calls a closure with an interface for writing to the specified file.
    ///
    /// This method automatically closes the file when its closure argument returns.
    /// -   Parameter path:
    ///     The path to the file to open.
    /// -   Parameter body:
    ///     A closure with a ``Destination`` parameter representing
    ///     the specified file to which data can be written to. This
    ///     interface is only valid for the duration of the method’s
    ///     execution. The closure is only executed if the specified file could
    ///     be successfully opened, otherwise this method will return `nil`.
    ///     If `body` has a return value and the specified file could be opened,
    ///     this method returns the return value of the closure.
    /// -   Returns:
    ///     The return value of the closure argument, or `nil` if the specified
    ///     file could not be opened.
    public static
    func open<R>(path:String, _ body:(inout Self) throws -> R)
        rethrows -> R?
    {
        guard let descriptor:System.File.Descriptor = fopen(path, "wb")
        else
        {
            return nil
        }

        var file:Self = .init(descriptor: descriptor)
        defer
        {
            fclose(file.descriptor)
        }

        return try body(&file)
    }

    /// Write the bytes in the given array to this file interface.
    ///
    /// This method only returns `()` if the entire array argument could
    /// be written. This method advances the file pointer.
    /// -   Parameter buffer:
    ///     The data to write.
    /// -   Returns:
    ///     A ``Void`` tuple if the entire array argument could be written,
    ///     or `nil` otherwise.
    public
    func write(_ buffer:[UInt8]) -> Void?
    {
        let count:Int = buffer.withUnsafeBufferPointer
        {
            #if os(Android)
            let baseAddress = $0.baseAddress!
            #else
            let baseAddress = $0.baseAddress
            #endif
            return fwrite(baseAddress, MemoryLayout<UInt8>.stride,
                $0.count, self.descriptor)
        }

        guard count == buffer.count
        else
        {
            return nil
        }

        return ()
    }
}

// declare conformance (as a formality)
extension System.File.Source:PNG.BytestreamSource
{
}
extension System.File.Destination:PNG.BytestreamDestination
{
}

extension PNG.Image
{
    /// Decompresses and decodes a PNG from a file at the given file path.
    ///
    /// This interface is only available on MacOS and Linux. The
    /// ``decompress(stream:)`` function provides a platform-independent
    /// decoding interface.
    /// -   Parameter path:
    ///     A path to a PNG file.
    /// -   Returns:
    ///     The decoded image, or `nil` if the file at the given `path` could
    ///     not be opened.
    public static
    func decompress(path:String) throws -> Self?
    {
        try System.File.Source.open(path: path)
        {
            try .decompress(stream: &$0)
        }
    }
    /// Encodes and compresses a PNG to a file at the given file path.
    ///
    /// Compression `level` `9` is roughly equivalent to *libpng*’s maximum
    /// compression setting in terms of compression ratio and encoding speed.
    /// The higher levels (`10` through `13`) are very computationally expensive,
    /// so they should only be used when optimizing for file size.
    ///
    /// Experimental comparisons between *Swift PNG* and *libpng*’s
    /// compression settings can be found on
    /// [this page](https://github.com/tayloraswift/swift-png/blob/master/benchmarks).
    ///
    /// This interface is only available on MacOS and Linux. The
    /// ``compress(stream:level:hint:)`` function provides a platform-independent
    /// encoding interface.
    /// -   Parameter path:
    ///     A path to save the PNG file at.
    /// -   Parameter level:
    ///     The compression level to use. It should be in the range `0 ... 13`,
    ///     where `13` is the most aggressive setting. The default value is `9`.
    ///
    ///     Setting this parameter to a value less than `0` is the same as
    ///     setting it to `0`. Likewise, setting it to a value greater than `13`
    ///     is the same as setting it to `13`.
    /// -   Parameter hint:
    ///     A size hint for the emitted ``Chunk/IDAT`` chunks. It should be in
    ///     the range `1 ... 2147483647`. Reasonable settings range from around
    ///     1&nbsp;K to 64&nbsp;K. The default value is `32768` (2<sup>5</sup>).
    ///
    ///     Setting this parameter to a value less than `1` is the same as setting
    ///     it to `1`. Likewise, setting it to a value greater than `2147483647`
    ///     (2<sup>31</sup>&nbsp;–&nbsp;1) is the same as setting it to `2147483647`.
    /// -   Returns:
    ///     A ``Void`` tuple if the destination file could be opened
    ///     successfully, or `nil` otherwise.
    public
    func compress(path:String, level:Int = 9, hint:Int = 1 << 15) throws -> Void?
    {
        try System.File.Destination.open(path: path)
        {
            try self.compress(stream: &$0, level: level, hint: hint)
        }
    }
}
#endif
