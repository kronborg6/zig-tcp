import * as net from "net";

const HEADER_SIZE = 10; // Must match Zig's header size

const client = new net.Socket();
client.connect(8080, "127.0.0.1", () => {
  console.log("Connected to Zig server");

  // Define header
  const buffer = Buffer.alloc(HEADER_SIZE);
  const length = 1234; // Length of body
  const version = 1;
  const msgType = "PING"; // Must be exactly 4 bytes

  // Write header in little-endian format
  buffer.writeUInt32LE(length, 0); // Body length (4 bytes)
  buffer.writeUInt16LE(version, 4); // Version (2 bytes)
  buffer.write(msgType, 6, 4, "ascii"); // Message type (4 bytes)

  // Define body
  const body = Buffer.from("Hello, Zig server!", "utf-8");

  // Send header + body
  client.write(Buffer.concat([buffer, body]));
});

// Handle server response
client.on("data", (data: any) => {
  console.log("Received:", data.toString());
});

// Handle disconnect
client.on("close", () => {
  console.log("Connection closed");
});

// Handle errors
client.on("error", (err) => {
  console.error("Error:", err);
});
