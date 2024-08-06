const std = @import("std");
const net = std.net;
const log = std.log;
const Args = @import("zig-args");
const Md5 = std.crypto.hash.Md5;

pub const std_options: std.Options = .{ .log_level = .info };

// Command line arguments struct
const Options = struct {
    help: bool = false,
    directory: []const u8 = ".",

    pub const shorthands = .{
        .h = "help",
        .d = "directory",
    };

    pub const meta = .{
        .usage_summary = "[-h] [-d directory] [host] [port]",
        .option_docs = .{
            .help = "Show this help",
            .directory = "Serve this directory (default: current directory)",
        },
    };
};

// struct used to send the client the info before sending the file
const Metadata = extern struct { md5sum: [Md5.digest_length]u8, filesize: u64 };

fn get(conn: net.Stream, dir: std.fs.Dir, file: []const u8) !void {
    // send file request to client
    try conn.writeAll(file);
    try conn.writeAll("\n");

    // receive metadata or err
    const metadata: Metadata = try conn.reader().readStruct(Metadata);
    if (std.mem.eql(u8, &metadata.md5sum, &[1]u8{0} ** Md5.digest_length)) {
        var buff: [100]u8 = undefined;
        const len = try conn.read(&buff);
        log.err("{s}", .{buff[0..len]});
        return;
    }
    log.info("md5sum => '{}'", .{std.fmt.fmtSliceHexLower(&metadata.md5sum)});

    // download file and do md5sum at the same time
    var md5 = Md5.init(.{});
    var digest: [Md5.digest_length]u8 = undefined;

    var buff: [2048]u8 = undefined;
    var output = try dir.createFile(file, .{});
    defer output.close();
    var bout = std.io.bufferedWriter(output.writer());
    defer bout.flush() catch {};

    var downloaded: u64 = 0;
    while (downloaded < metadata.filesize) {
        const len = try conn.read(&buff);
        _ = try bout.writer().write(buff[0..len]);
        md5.update(buff[0..len]);
        downloaded += len;
        log.info("downloaded {d}/{d} bytes", .{ downloaded, metadata.filesize });
    }
    md5.final(&digest);

    // check md5sum
    if (std.mem.eql(u8, &digest, &metadata.md5sum)) {
        log.info("calculated md5sum matches !", .{});
    } else {
        log.err("calculated md5sum does not match => '{s}'", .{std.fmt.fmtSliceHexLower(&digest)});
    }
}

fn download(addr: net.Address, dir: []const u8) !void {
    var conn = try net.tcpConnectToAddress(addr);
    defer conn.close();
    log.info("Connected to {} and downloading to {s}/", .{ addr, dir });

    var directory = try std.fs.cwd().openDir(dir, .{});
    defer directory.close();

    var buff: [1024]u8 = undefined;
    var bin = std.io.bufferedReader(std.io.getStdIn().reader());
    std.debug.print("> ", .{});
    const path = try bin.reader().readUntilDelimiterOrEof(&buff, '\n') orelse return;
    try get(conn, directory, path);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("leak detected");
    const allocator = gpa.allocator();

    // parse arguments
    const args = Args.parseForCurrentProcess(Options, allocator, .print) catch return;
    defer args.deinit();
    if (args.positionals.len != 2) {
        try Args.printHelp(
            Options,
            args.executable_name orelse "zfs_client",
            std.io.getStdOut().writer(),
        );
        return;
    }

    // parse address
    const ip = args.positionals[0];
    const port = try std.fmt.parseUnsigned(u16, args.positionals[1], 10);
    const addr = try net.Address.parseIp(ip, port);

    // remove trailing / from directory path
    const dir = std.mem.trimRight(u8, args.options.directory, "/");

    try download(addr, dir);
}
