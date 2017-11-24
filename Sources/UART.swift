/*
 SwiftyGPIO

 Copyright (c) 2016 Umberto Raimondi
 Licensed under the MIT license, as follows:

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.)
 */
#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

import Foundation

extension SwiftyGPIO {

    public static func UARTs(for board: SupportedBoard) -> [UARTInterface]? {
        switch board {
        case .CHIP:
            return [SysFSUART(["serial0","ttyAMA0"])].flatMap { $0 }
        case .RaspberryPiRev1:
            fallthrough
        case .RaspberryPiRev2:
            fallthrough
        case .RaspberryPiPlusZero:
            fallthrough
        case .RaspberryPi2:
            return [SysFSUART(["serial0","ttyAMA0"])].flatMap { $0 }
        case .RaspberryPi3:
            return [SysFSUART(["serial0","ttyS0"]),
                    SysFSUART(["serial1","ttyAMA0"])].flatMap { $0 }
        default:
            return nil
        }
    }
}

// MARK: UART
public protocol UARTInterface {
    func configureInterface(speed: UARTSpeed, bitsPerChar: CharSize, stopBits: StopBits, parity: ParityType)
    func readString() -> String?
    func readLine() -> String?
    func readChars() -> [CChar]?
    func readByte() -> UInt8?
    func write(string value: String)
    func write(chars values: [CChar])
    func write(data values: Data)
}

public enum ParityType {
    case None
    case Even
    case Odd

    public func configure(_ cfg: inout termios) {
        switch self {
        case .None:
            cfg.c_cflag &= ~UInt32(PARENB | PARODD)
        case .Even:
            cfg.c_cflag &= ~UInt32(PARENB | PARODD)
            cfg.c_cflag |= UInt32(PARENB)
        case .Odd:
            cfg.c_cflag |= UInt32(PARENB | PARODD)
        }
    }
}

public enum CharSize {
    case Eight
    case Seven
    case Six

    public func configure(_ cfg: inout termios) {
        cfg.c_cflag = (cfg.c_cflag & ~UInt32(CSIZE))
        switch self {
        case .Eight:
            cfg.c_cflag |= UInt32(CS8)
        case .Seven:
            cfg.c_cflag |= UInt32(CS7)
        case .Six:
            cfg.c_cflag |= UInt32(CS6)
        }
    }
}

public enum StopBits {
    case One
    case Two

    public func configure(_ cfg: inout termios) {
        switch self {
        case .One:
            cfg.c_cflag &= ~UInt32(CSTOPB)
        case .Two:
            cfg.c_cflag |= UInt32(CSTOPB)
        }
    }
}

public enum UARTSpeed {
    case S2400
    case S4800
    case S9600
    case S19200
    case S38400
    case S57600
    case S115200

    public func configure(_ cfg: inout termios) {
        switch self {
        case .S2400:
            cfsetispeed(&cfg, speed_t(B2400))
            cfsetospeed(&cfg, speed_t(B2400))
        case .S4800:
            cfsetispeed(&cfg, speed_t(B4800))
            cfsetospeed(&cfg, speed_t(B4800))
        case .S9600:
            cfsetispeed(&cfg, speed_t(B9600))
            cfsetospeed(&cfg, speed_t(B9600))
        case .S19200:
            cfsetispeed(&cfg, speed_t(B19200))
            cfsetospeed(&cfg, speed_t(B19200))
        case .S38400:
            cfsetispeed(&cfg, speed_t(B38400))
            cfsetospeed(&cfg, speed_t(B38400))
        case .S57600:
            cfsetispeed(&cfg, speed_t(B57600))
            cfsetospeed(&cfg, speed_t(B57600))
        case .S115200:
            cfsetispeed(&cfg, speed_t(B115200))
            cfsetospeed(&cfg, speed_t(B115200))
        }
    }
}

/// UART via SysFS
public final class SysFSUART: UARTInterface {
    var device: String
    var tty: termios
    var fd: Int32

    public init?(_ uartIdList: [String]) {
        // try all items in list until one works
        for uartId in uartIdList {

            device = "/dev/"+uartId
            tty = termios()

            fd = open(device, O_RDWR | O_NOCTTY | O_SYNC)
            guard fd>0 else {
                if errno == ENOENT {
                    // silently return nil if no such device
                    continue
                }
                perror("Couldn't open UART device")
                continue
            }

            let ret = tcgetattr(fd, &tty)

            guard ret == 0 else {
	        close(fd)
                perror("Couldn't get terminal attributes")
                continue
            }

            return
	}

        return nil
    }

    public convenience init?(_ uartId: String) {
        self.init([uartId])
    }

    public func configureInterface(speed: UARTSpeed, bitsPerChar: CharSize, stopBits: StopBits, parity: ParityType) {
        speed.configure(&tty)

        bitsPerChar.configure(&tty)
        tty.c_iflag &= ~UInt32(IGNBRK)      // disable break processing
        tty.c_lflag =  0    				// no signaling chars, no echo,
        // no canonical processing -> read bytes as they come without waiting for LF
        tty.c_oflag = 0                     // no remapping, no delays

        withUnsafeMutableBytes(of: &tty.c_cc) {$0[Int(VMIN)] = UInt8(1); return}
        withUnsafeMutableBytes(of: &tty.c_cc) {$0[Int(VTIME)] = UInt8(5); return} // 5 10th of second read timeout
        tty.c_iflag &= ~UInt32(IXON | IXOFF | IXANY) // Every kind of software flow control off
        tty.c_cflag &= ~UInt32(CRTSCTS)  //No hw flow control
        tty.c_cflag |= UInt32(CLOCAL | CREAD)        // Ignore modem controls, enable read
        parity.configure(&tty)
        stopBits.configure(&tty)

        applyConfiguration()
    }

    public func readLine() -> String? {
        var buf = [CChar](repeating:0, count: 4097) //4096 chars at max in canonical mode
        var ptr = UnsafeMutablePointer<CChar>(&buf)
        var pos = 0

        repeat {
            let n = read(fd, ptr, MemoryLayout<CChar>.stride)
            if n<0 {
                perror("Error while reading from UART")
                abort()
            }

            if n == 0 {
                return nil
            }
            ptr += 1
            pos += 1
        } while buf[pos-1] != CChar(UInt8(ascii: "\n"))

        buf[pos] = 0
        return String(cString: &buf)
    }

    public func readString() -> String? {
        var buf = readChars()
        if buf == nil {
            return nil
        }
        buf!.append(0) //Add terminator to convert cString correctly
        return String(cString: &buf!)
    }

    public func readChars() -> [CChar]? {
        var buf = [CChar](repeating:0, count: 4096) //4096 chars at max in canonical mode

        let n = read(fd, &buf, buf.count * MemoryLayout<CChar>.stride)
        if n<0 {
            perror("Error while reading from UART")
            abort()
        }
        if n == 0 {
            return nil
        }
        return Array(buf[0..<n])
    }

    public func readByte() -> UInt8? {
        var buf = [UInt8](repeating:0, count:1)

        let n = read(fd, &buf, 1)
        if n<0 {
            perror("Error while reading from UART")
            abort()
        }
        if n == 0 {
            return nil
        }
        return buf[0]
    }

    public func write(byte value: CChar) {
        var value = value

        _ = Glibc.write(fd, &value, 1)
        tcdrain(fd)
    }
    
    public func write(string value: String) {
        let chars = Array(value.utf8CString)

        write(chars:chars)
    }

    public func write(chars value: [CChar]) {
        var value = value

        _ = Glibc.write(fd, &value, value.count)
        tcdrain(fd)
    }

    public func write(data value:Data) {
        value.withUnsafeBytes {(bytes: UnsafePointer<CChar>)->Void in
            _ = Glibc.write(fd, bytes, value.count)
            tcdrain(fd)
        }
    }

    private func applyConfiguration() {
        if tcsetattr (fd, TCSANOW, &tty) != 0 {
            perror("Couldn't set terminal attributes")
            abort()
        }
    }

    deinit {
        close(fd)
    }

}

// MARK: - Darwin / Xcode Support
#if os(OSX)
    private var O_SYNC: CInt { fatalError("Linux only") }
    private var CRTSCTS: CInt { fatalError("Linux only") }

    // Shadowing some declarations from termios.h just to get it to compile with Xcode
    // As the rest, not atually intended to be run.
    public struct termios {
        var c_iflag: UInt32 = 0
        var c_oflag: UInt32 = 0
        var c_cflag: UInt32 = 0
        var c_lflag: UInt32 = 0
        var c_cc = [UInt32]()
    }

    func tcsetattr (_ fd: Int32, _ attr: Int32, _ tty: inout termios) -> Int { fatalError("Linux only") }
    func tcgetattr(_ fd: Int32, _ tty: inout termios) -> Int { fatalError("Linux only") }
    func cfsetispeed(_ tty: inout termios, _ speed: UInt) { fatalError("Linux only") }
    func cfsetospeed(_ tty: inout termios, _ speed: UInt) { fatalError("Linux only") }

#endif
