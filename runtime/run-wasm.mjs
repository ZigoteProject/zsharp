// Runs a program built with zs build --target wasm32 under Node: node run-wasm.mjs prog.wasm.
// The host's side of rt-embedded.c: zs.write (bytes, length) to standard output, zs.exit (code)
// ends the run, zs.ticks () counts microseconds. A browser host gives the same three imports.
import { readFileSync, writeSync } from "node:fs";

class Exit {
  constructor(code) { this.code = code; }
}

let memory;
const imports = {
  zs: {
    write: (p, n) => writeSync(1, new Uint8Array(memory.buffer, p, n)),
    exit: (code) => { throw new Exit(code); },
    ticks: () => process.hrtime.bigint() / 1000n,
  },
};
const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), imports);
memory = instance.exports.memory;
try {
  instance.exports._start();
} catch (e) {
  if (!(e instanceof Exit)) throw e;
  process.exitCode = e.code;
}
