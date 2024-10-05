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

let verbose = CommandLine.argc > 4

let DEST_ADDR: SocketAddress = if let v4 = try? sockaddr_in.inet(ip4: remoteHost, port: remotePort) {
    v4
} else if let v6 = try? sockaddr_in6.inet6(ip6: remoteHost, port: remotePort) {
    v6
} else {
    fatalError("Unable to create remote address")
}

let BUF_SIZE = 1024

func logOut(uuid: UUID, host: String, port: UInt16, data: Data) -> String {
    if let str = String(bytes: data, encoding: .utf8) {
        return "-> \(data.count) bytes:\t" + str
    }
    return "-> \(data.count) bytes"
}
// let logIn = { (uuid: UUID, host: String, port: UInt16, data: Data) in // gives errors about not beign run on @MainActor
func logIn(uuid: UUID, host: String, port: UInt16, data: Data) -> String {
    if let str = String(bytes: data, encoding: .utf8) {
        return "<- \(data.count) bytes:\t" + str
    }
    return "<- \(data.count) bytes"
}

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

    let addr: String
    let port: UInt16

    switch try con.socket.remotePeer() {
    case let .ip4(ip, _port):
        addr = ip
        port = _port
        print("[\(uuid)] Connected from \(ip):\(_port)")
    case let .ip6(ip, _port):
        addr = ip
        port = _port
        print("[\(uuid)] Connected from [\(ip)]:\(_port)")
    case let .unix(path):
        print("[\(uuid)] Connected from \(path)")
        fatalError("This should never happen!")
    }

    print("[\(uuid)] Connecting to remote...")
    let outgoing = try await AsyncSocket.connected(to: DEST_ADDR)
    print("[\(uuid)] Connected to remote!")

    Task {
        try await withThrowingTaskGroup(of: Void.self) { group -> Void in
            group.addTask {
                while true {
                    do {
                        let data = try await Data(con.read(atMost: BUF_SIZE))
                        print("[\(uuid)] Read \(data.count) bytes from socket: \(String(describing: String(bytes: data, encoding: .utf8)))")

                        print(logOut(uuid: uuid, host: addr, port: port, data: data))

                        try await outgoing.write(data)
                        print("[\(uuid)] Wrote \(data.count) bytes to socket")
                    } catch is CancellationError {
                        // The other socket closed
                        try con.close()
                    } catch SocketError.disconnected {
                        print("[\(uuid)] disconnected")
                        throw SocketError.disconnected
                    } catch {
                        print("[\(uuid)] error: \(error)")
                        print(type(of: error))
                        throw error
                    }
                }
            }
            group.addTask {
                while true {
                    do {
                        let data = try await Data(outgoing.read(atMost: BUF_SIZE))
                        print("[\(uuid)] Read \(data.count) bytes from socket: \(String(describing: String(bytes: data, encoding: .utf8)))")

                        print(logIn(uuid: uuid, host: addr, port: port, data: data))

                        try await con.write(data)
                        print("[\(uuid)] Wrote \(data.count) bytes to socket")
                    } catch is CancellationError {
                        // The other socket closed
                        try outgoing.close()
                    } catch SocketError.disconnected {
                        print("[\(uuid)] disconnected")
                        throw SocketError.disconnected
                    } catch {
                        print("[\(uuid)] error: \(error)")
                        print(type(of: error))
                        throw error
                    }
                }
            }
            try await group.next() // This propagates errors, which cancels the other child task
        }
    }
}
