const net = require("net");
const { Buffer } = require("buffer");

const HEADER_SIZE = 8; // 4 bytes (length) + 2 bytes (version) + 2 bytes (msgType)

const client = new net.Socket();
client.connect(5882, "127.0.0.1", () => {
  // console.log("Connected to Zig server");

  // Define header
  const body = Buffer.from("Hello im Index2", "utf-8");
  const bodyLength = body.length;
  const buffer = Buffer.alloc(HEADER_SIZE);
  const version = 1;
  const msgType = 42; // Example: Message type as a u16 (2 bytes)

  // Write header in little-endian format
  buffer.writeUInt32LE(bodyLength, 0); // Body length (4 bytes)
  buffer.writeUInt16LE(version, 4); // Version (2 bytes)
  buffer.writeUInt16LE(msgType, 6); // Message type (2 bytes)

  // Define body

  // Send header + body
  client.write(Buffer.concat([buffer, body]));
  setTimeout(() => {
    // console.log("After sleep");
    const body = Buffer.from("Okay", "utf-8");
    const bodyLength = body.length;
    const buffer = Buffer.alloc(HEADER_SIZE);
    const version = 1;
    const msgType = 42; // Example: Message type as a u16 (2 bytes)

    // Write header in little-endian format
    buffer.writeUInt32LE(bodyLength, 0); // Body length (4 bytes)
    buffer.writeUInt16LE(version, 4); // Version (2 bytes)
    buffer.writeUInt16LE(msgType, 6); // Message type (2 bytes)
    client.write(Buffer.concat([buffer, body]));
  }, 10000); // Sleeps for 2 seconds (2000ms)
});

// Handle server response
client.on("data", (data) => {
  console.log("Index:", data.toString());
});

// Handle disconnect
client.on("close", () => {
  console.log("Connection closed");
});

// // Handle errors
client.on("error", (err) => {
  console.error("Error:", err);
});
