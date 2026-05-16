const TEXT_DECODER = new TextDecoder('ascii');

function readUint32(data, offset) {
  return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
}

function readBoxType(data, offset) {
  return TEXT_DECODER.decode(data.subarray(offset, offset + 4));
}

function readBoxHeader(data, offset) {
  if (offset + 8 > data.length) return null;
  let size = readUint32(data, offset);
  const type = readBoxType(data, offset + 4);
  let headerSize = 8;

  if (size === 1) {
    if (offset + 16 > data.length) return null;
    const hi = readUint32(data, offset + 8);
    const lo = readUint32(data, offset + 12);
    size = hi * 0x100000000 + lo;
    headerSize = 16;
  } else if (size === 0) {
    size = data.length - offset;
  }

  return { type, size, headerSize, offset };
}

function* iterateBoxes(data, start, end) {
  let pos = start;
  while (pos < end) {
    const box = readBoxHeader(data, pos);
    if (!box || box.size < 8) break;
    yield box;
    pos += box.size;
  }
}

function findBox(data, start, end, type) {
  for (const box of iterateBoxes(data, start, end)) {
    if (box.type === type) return box;
  }
  return null;
}

function findBoxPath(data, start, end, path) {
  let s = start;
  let e = end;
  for (const type of path) {
    const box = findBox(data, s, e, type);
    if (!box) return null;
    s = box.offset + box.headerSize;
    e = box.offset + box.size;
  }
  return { start: s, end: e };
}

function parseAvcCodecString(data, offset, end) {
  for (const box of iterateBoxes(data, offset, end)) {
    if (box.type === 'avcC' && box.size >= 12) {
      const base = box.offset + box.headerSize;
      const profile = data[base + 1];
      const compat = data[base + 2];
      const level = data[base + 3];
      return `avc1.${hex2(profile)}${hex2(compat)}${hex2(level)}`;
    }
  }
  return 'avc1.42E01E';
}

function parseHevcCodecString() {
  return 'hev1.1.6.L93.B0';
}

function parseVp9CodecString() {
  return 'vp09.00.10.08';
}

function hex2(n) {
  return n.toString(16).padStart(2, '0').toUpperCase();
}

function parseStsd(data, stsdStart, stsdEnd) {
  if (stsdEnd - stsdStart < 8) return null;
  const entryCount = readUint32(data, stsdStart + 4);
  if (entryCount === 0) return null;

  const videoCodecs = [];
  const audioCodecs = [];
  let pos = stsdStart + 8;

  for (let i = 0; i < entryCount && pos < stsdEnd; i++) {
    const entry = readBoxHeader(data, pos);
    if (!entry) break;
    const entryType = entry.type;
    const entryInner = entry.offset + entry.headerSize;
    const entryEnd = entry.offset + entry.size;

    if (entryType === 'avc1' || entryType === 'avc3') {
      const codecInner = entryInner + 78; // skip sample entry fields
      videoCodecs.push(parseAvcCodecString(data, codecInner, entryEnd));
    } else if (entryType === 'hev1' || entryType === 'hvc1') {
      videoCodecs.push(parseHevcCodecString());
    } else if (entryType === 'vp09') {
      videoCodecs.push(parseVp9CodecString());
    } else if (entryType === 'mp4a') {
      audioCodecs.push('mp4a.40.2');
    } else if (entryType === 'Opus') {
      audioCodecs.push('opus');
    }

    pos += entry.size;
  }

  return { videoCodecs, audioCodecs };
}

function buildMimeString(container, videoCodecs, audioCodecs) {
  const allCodecs = [...videoCodecs, ...audioCodecs];
  if (allCodecs.length === 0) return null;
  return `${container}; codecs="${allCodecs.join(',')}"`;
}

export function hasMoovAtom(data) {
  for (const box of iterateBoxes(data, 0, data.length)) {
    if (box.type === 'moov') return true;
  }
  return false;
}

export function parseCodecString(data) {
  const hasMoov = hasMoovAtom(data);
  if (!hasMoov) return { codecString: null, hasMoov: false };

  let container = 'video/mp4';
  for (const box of iterateBoxes(data, 0, data.length)) {
    if (box.type === 'ftyp') {
      const brand = readBoxType(data, box.offset + box.headerSize);
      if (brand === 'webm') container = 'video/webm';
      break;
    }
  }

  const results = [];
  for (const moovBox of iterateBoxes(data, 0, data.length)) {
    if (moovBox.type !== 'moov') continue;
    const moovStart = moovBox.offset + moovBox.headerSize;
    const moovEnd = moovBox.offset + moovBox.size;

    for (const trakBox of iterateBoxes(data, moovStart, moovEnd)) {
      if (trakBox.type !== 'trak') continue;
      const trakStart = trakBox.offset + trakBox.headerSize;
      const trakEnd = trakBox.offset + trakBox.size;

      const stsd = findBoxPath(data, trakStart, trakEnd, ['mdia', 'minf', 'stbl', 'stsd']);
      if (!stsd) continue;

      const parsed = parseStsd(data, stsd.start, stsd.end);
      if (parsed) results.push(parsed);
    }
    break;
  }

  const videoCodecs = results.flatMap(r => r.videoCodecs);
  const audioCodecs = results.flatMap(r => r.audioCodecs);
  const codecString = buildMimeString(container, videoCodecs, audioCodecs);

  return { codecString, hasMoov: true };
}
