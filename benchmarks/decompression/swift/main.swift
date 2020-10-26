// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
import PNG

#if os(macOS)
import func Darwin.nanosleep
import struct Darwin.timespec
import func Darwin.clock
import var Darwin.CLOCKS_PER_SEC
func clock() -> Int
{
    .init(Darwin.clock())
}

#elseif os(Linux)
import func Glibc.nanosleep
import struct Glibc.timespec
import func Glibc.clock
import var Glibc.CLOCKS_PER_SEC
func clock() -> Int
{
    Glibc.clock()
}

#else
    #warning("clock() function not imported for this platform, internal benchmarks not built (please open an issue at https://github.com/kelvin13/png/issues)")
#endif

#if os(macOS) || os(Linux)

struct Blob:PNG.Bytestream.Source 
{
    private 
    let buffer:[UInt8] 
    private(set)
    var count:Int 
    
    static 
    func load(path:String) -> Self? 
    {
        System.File.Source.open(path: path) 
        {
            (file:inout System.File.Source) -> Self? in 
            guard   let count:Int       = file.count, 
                    let buffer:[UInt8]  = file.read(count: count)
            else 
            {
                return nil 
            }
            return .init(buffer: buffer, count: count)
        } ?? nil 
    }
    
    mutating 
    func read(count:Int) -> [UInt8]?
    {
        guard count <= self.count 
        else 
        {
            return nil 
        }
        let data:[UInt8] = .init(self.buffer.suffix(self.count).prefix(count))
        self.count      -= count 
        return data
    }
    
    mutating 
    func reload() 
    {
        self.count = self.buffer.count
    }
}

// internal benchmarking functions, to measure module boundary overhead
enum Benchmark 
{
    enum Decode 
    {
    }
    
    struct Blob:PNG.Bytestream.Source 
    {
        private 
        let buffer:[UInt8] 
        private(set)
        var count:Int 
    }
}
extension Benchmark.Blob 
{
    static 
    func load(path:String) -> Self? 
    {
        System.File.Source.open(path: path) 
        {
            (file:inout System.File.Source) -> Self? in 
            guard   let count:Int       = file.count, 
                    let buffer:[UInt8]  = file.read(count: count)
            else 
            {
                return nil 
            }
            return .init(buffer: buffer, count: count)
        } ?? nil 
    }
    
    mutating 
    func read(count:Int) -> [UInt8]?
    {
        guard count <= self.count 
        else 
        {
            return nil 
        }
        let data:[UInt8] = .init(self.buffer.suffix(self.count).prefix(count))
        self.count      -= count 
        return data
    }
    
    mutating 
    func reload() 
    {
        self.count = self.buffer.count
    }
}
extension Benchmark.Decode
{
    static
    func rgba8(path:String, trials:Int) -> [(time:Int, hash:Int)]
    {
        guard var blob:Benchmark.Blob = .load(path: path)
        else 
        {
            fatalError("could not read file '\(path)'")
        }
        
        return (0 ..< trials).map 
        {
            _ in 
            // sleep for 0.1s between runs to emulate a “cold” start
            nanosleep([timespec.init(tv_sec: 0, tv_nsec: 100_000_000)], nil)
            blob.reload()
            
            do 
            {
                let start:Int = clock()
                
                let image:PNG.Data.Rectangular  = try .decompress(stream: &blob)
                let pixels:[PNG.RGBA<UInt8>]    = image.unpack(as: PNG.RGBA<UInt8>.self)
                
                let stop:Int = clock()
                return (stop - start, .init(pixels.last?.r ?? 0))
            }
            catch let error
            {
                fatalError("\(error)")
            }
        }
    }
}

func main() throws
{
    guard let path:String = CommandLine.arguments.dropFirst(1).first, 
        2 ... 3 ~= CommandLine.arguments.count
    else 
    {
        fatalError("usage: \(CommandLine.arguments.first ?? "") <image>")
    }
    guard let trials:Int = Int.init(CommandLine.arguments.dropFirst(2).first ?? "1")
    else 
    {
        fatalError("'\(CommandLine.arguments.dropFirst(2).first ?? "")' is not a valid integer")
    }
    
    #if INTERNAL_BENCHMARKS
    let times:[Int] =              Benchmark.Decode.rgba8(path: path, trials: trials).map(\.time)
    #else 
    let times:[Int] = __Entrypoint.Benchmark.Decode.rgba8(path: path, trials: trials).map(\.time)
    #endif
    
    for time:Int in times 
    {
        print("\(1000.0 * .init(time) / .init(CLOCKS_PER_SEC))")
    }
}

try main()

#endif
