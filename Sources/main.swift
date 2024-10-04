import FlyingSocks
import Foundation

// MARK: - parse arguments

guard CommandLine.argc >= 4 else {
    print("Usage: \(CommandLine.arguments[0]) <localPort> <remoteHost> <remotePort> [verbose]")
    exit(1)
}

guard let localPort = UInt16(CommandLine.arguments[1]) else {
    print("localPort must be an integer")
    exit(1)
}
let remoteHost = CommandLine.arguments[2]
guard let remotePort = UInt16(CommandLine.arguments[3]) else {
    print("remotePort must be an integer")
    exit(1)
}

let DEST_ADDR: SocketAddress = if let v4 = try? sockaddr_in.inet(ip4: remoteHost, port: remotePort) {
    v4
} else if let v6 = try? sockaddr_in6.inet6(ip6: remoteHost, port: remotePort) {
    v6
} else {
    fatalError()
}

let BUF_SIZE = 1024

// MARK: - main logic

let _socket = try Socket(domain: AF_INET, type: SOCK_STREAM)

try _socket.bind(to: .inet(port: localPort))
try _socket.listen()

let pool = SocketPool<Poll>.make()

let serverSocket = try AsyncSocket(socket: _socket, pool: pool)

try await pool.prepare()

Task {
    try await pool.run()
}

for try await con in serverSocket.sockets {
    let uuid = UUID()

    switch try con.socket.remotePeer() {
    case let .ip4(ip, port):
        print("[\(uuid)] Connected from \(ip):\(port)")
    case let .ip6(ip, port):
        print("[\(uuid)] Connected from [\(ip)]:\(port)")
    case let .unix(path):
        print("[\(uuid)] Connected from \(path)")
    }

    print("[\(uuid)] Connecting to remote...")
    let outgoing = try await AsyncSocket.connected(to: DEST_ADDR)
    print("[\(uuid)] Connected to remote!")

    Task {
        while true {
            do {
                let data = try await con.read(atMost: BUF_SIZE)
                print("[\(uuid)] Read \(data.count) bytes from socket: \(String(describing: String(bytes: data, encoding: .utf8)))")

                try await outgoing.write(Data(data))
                print("[\(uuid)] Wrote \(data.count) bytes to socket")
            } catch {
                print("[\(uuid)] error: \(error)")
                break
            }
        }
    }

    Task {
        while true {
            do {
                let data = try await outgoing.read(atMost: BUF_SIZE)
                print("[\(uuid)] Read \(data.count) bytes from socket: \(String(describing: String(bytes: data, encoding: .utf8)))")

                try await con.write(Data(data))
                print("[\(uuid)] Wrote \(data.count) bytes to socket")
            } catch {
                print("[\(uuid)] error: \(error)")
                break
            }
        }
    }
}

//1024 byte buffer
