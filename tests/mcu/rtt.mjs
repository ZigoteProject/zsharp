// The host's side of RTT (0027), for tests: given a dump of a board's RAM from 0x20000000, the
// bytes its first up channel holds unread, the control block found by its ID as a probe finds it.
import { readFileSync } from "node:fs";

const ram = readFileSync(process.argv[2]);
const up = ram.indexOf("SEGGER RTT\0") + 24; // past the ID and the channel counts
const at = (offset) => ram.readUInt32LE(up + offset);
const [buf, size, wr, rd] = [at(4) - 0x20000000, at(8), at(12), at(16)];
const ring = ram.subarray(buf, buf + size);
process.stdout.write(wr >= rd ? ring.subarray(rd, wr) : Buffer.concat([ring.subarray(rd), ring.subarray(0, wr)]));
