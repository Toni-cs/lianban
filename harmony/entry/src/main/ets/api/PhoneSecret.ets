import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const KEM_SUITE: Uint8Array = new Uint8Array([0x4b, 0x45, 0x4d, 0x00, 0x10]);
const HPKE_SUITE: Uint8Array = new Uint8Array([
  0x48, 0x50, 0x4b, 0x45, 0x00, 0x10, 0x00, 0x01, 0x00, 0x02
]);
const INFO_TEXT: string = 'OpenMausBot phone credential v1';
const P256_SPKI_PREFIX: Uint8Array = new Uint8Array([
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
]);

export class PhoneSecretSealInput {
  publicKey: string = '';
  deviceId: string = '';
  botId: string = '';
  threadId: string = '';
  messageId: string = '';
  target: string = '';
  requestKey: string = '';
}

export class PhoneSecretEnvelope {
  keyId: string = '';
  encapsulatedKey: string = '';
  ciphertext: string = '';
}

function blob(data: Uint8Array): cryptoFramework.DataBlob {
  const value: cryptoFramework.DataBlob = { data: data };
  return value;
}

function copyBytes(source: Uint8Array): Uint8Array {
  const out = new Uint8Array(source.length);
  out.set(source);
  return out;
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let i = 0; i < parts.length; i++) {
    total += parts[i].length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (let i = 0; i < parts.length; i++) {
    out.set(parts[i], offset);
    offset += parts[i].length;
  }
  return out;
}

function ascii(value: string): Uint8Array {
  const out = new Uint8Array(value.length);
  for (let i = 0; i < value.length; i++) {
    out[i] = value.charCodeAt(i) & 0xff;
  }
  return out;
}

function utf8(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < value.length; i++) {
    let code = value.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < value.length) {
      const next = value.charCodeAt(i + 1);
      code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
      i += 1;
      bytes.push((code >> 18) | 0xf0);
      bytes.push(((code >> 12) & 0x3f) | 0x80);
      bytes.push(((code >> 6) & 0x3f) | 0x80);
      bytes.push((code & 0x3f) | 0x80);
    } else if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push((code >> 6) | 0xc0);
      bytes.push((code & 0x3f) | 0x80);
    } else {
      bytes.push((code >> 12) | 0xe0);
      bytes.push(((code >> 6) & 0x3f) | 0x80);
      bytes.push((code & 0x3f) | 0x80);
    }
  }
  return numbersToBytes(bytes);
}

function u16(length: number): Uint8Array {
  const out = new Uint8Array(2);
  out[0] = (length >> 8) & 0xff;
  out[1] = length & 0xff;
  return out;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const triple = (b0 << 16) | (b1 << 8) | b2;
    out += alphabet.charAt((triple >> 18) & 63);
    out += alphabet.charAt((triple >> 12) & 63);
    if (i + 1 < bytes.length) {
      out += alphabet.charAt((triple >> 6) & 63);
    }
    if (i + 2 < bytes.length) {
      out += alphabet.charAt(triple & 63);
    }
    i += 3;
  }
  return out.replace(/\+/g, '-').replace(/\//g, '_');
}

function base64UrlToBytes(value: string): Uint8Array {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  while (normalized.length % 4 !== 0) {
    normalized += '=';
  }
  const bytes: number[] = [];
  for (let i = 0; i < normalized.length; i += 4) {
    const a = alphabet.indexOf(normalized.charAt(i));
    const b = alphabet.indexOf(normalized.charAt(i + 1));
    const c = alphabet.indexOf(normalized.charAt(i + 2));
    const d = alphabet.indexOf(normalized.charAt(i + 3));
    if (a < 0 || b < 0) {
      break;
    }
    bytes.push((a << 2) | (b >> 4));
    if (normalized.charAt(i + 2) !== '=' && c >= 0) {
      bytes.push(((b & 15) << 4) | (c >> 2));
    }
    if (normalized.charAt(i + 3) !== '=' && d >= 0) {
      bytes.push(((c & 3) << 6) | d);
    }
  }
  return numbersToBytes(bytes);
}

function numbersToBytes(bytes: number[]): Uint8Array {
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[i] = bytes[i];
  }
  return out;
}

function hmacSha256(key: Uint8Array, data: Uint8Array): Uint8Array {
  const generator = cryptoFramework.createSymKeyGenerator('HMAC');
  const symKey = generator.convertKeySync(blob(key));
  const mac = cryptoFramework.createMac('SHA256');
  mac.initSync(symKey);
  mac.updateSync(blob(data));
  return copyBytes(mac.doFinalSync().data);
}

function sha256(data: Uint8Array): Uint8Array {
  const digest = cryptoFramework.createMd('SHA256');
  digest.updateSync(blob(data));
  return copyBytes(digest.digestSync().data);
}

function labeledExtract(suite: Uint8Array, salt: Uint8Array, label: string, ikm: Uint8Array): Uint8Array {
  const used = salt.length > 0 ? salt : new Uint8Array(32);
  const labeled = concatBytes([ascii('HPKE-v1'), suite, ascii(label), ikm]);
  return hmacSha256(used, labeled);
}

function labeledExpand(suite: Uint8Array, prk: Uint8Array, label: string, info: Uint8Array, length: number): Uint8Array {
  const labeled = concatBytes([u16(length), ascii('HPKE-v1'), suite, ascii(label), info]);
  const out = new Uint8Array(length);
  let previous = new Uint8Array(0);
  let filled = 0;
  let counter = 1;
  while (filled < length) {
    const block = hmacSha256(prk, concatBytes([previous, labeled, new Uint8Array([counter])]));
    const take = Math.min(block.length, length - filled);
    out.set(block.subarray(0, take), filled);
    previous = block;
    filled += take;
    counter += 1;
  }
  return out;
}

function sharedSecret(dh: Uint8Array, enc: Uint8Array, recipient: Uint8Array): Uint8Array {
  const dh32 = dh.length === 32 ? dh : pad32(dh);
  const prk = labeledExtract(KEM_SUITE, new Uint8Array(0), 'eae_prk', dh32);
  return labeledExpand(KEM_SUITE, prk, 'shared_secret', concatBytes([enc, recipient]), 32);
}

function pad32(value: Uint8Array): Uint8Array {
  if (value.length === 32) {
    return value;
  }
  const out = new Uint8Array(32);
  if (value.length > 32) {
    out.set(value.subarray(value.length - 32));
    return out;
  }
  out.set(value, 32 - value.length);
  return out;
}

function uncompressedPoint(encoded: Uint8Array): Uint8Array {
  if (encoded.length === 65 && encoded[0] === 4) {
    return copyBytes(encoded);
  }
  if (encoded.length >= 65 && encoded[encoded.length - 65] === 4) {
    return copyBytes(encoded.subarray(encoded.length - 65));
  }
  throw new Error('电脑公钥格式无法识别');
}

function sealAes(key: Uint8Array, nonce: Uint8Array, aad: Uint8Array, plain: Uint8Array): Uint8Array {
  const generator = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey = generator.convertKeySync(blob(key));
  const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
  const tag = new Uint8Array(16);
  const params: cryptoFramework.GcmParamsSpec = {
    iv: blob(nonce),
    aad: blob(aad),
    authTag: blob(tag),
    algName: 'GcmParamsSpec'
  };
  cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
  const encrypted = cipher.doFinalSync(blob(plain));
  const body = copyBytes(encrypted.data);
  const auth = copyBytes(params.authTag.data);
  if (body.length === plain.length + 16) {
    return body;
  }
  return concatBytes([body, auth]);
}

function credentialAad(input: PhoneSecretSealInput, keyId: string): Uint8Array {
  const lines = [
    'openmausbot-phone-credential-v1',
    keyId,
    input.deviceId,
    input.botId,
    input.threadId,
    input.messageId,
    input.target,
    input.requestKey
  ];
  return ascii(lines.join('\n'));
}

export function sealPhoneSecret(input: PhoneSecretSealInput, plaintext: string): PhoneSecretEnvelope {
  const recipient = base64UrlToBytes(input.publicKey.trim());
  if (recipient.length !== 65 || recipient[0] !== 4) {
    throw new Error('电脑没有给出可用的公钥，请重新扫码配对');
  }
  const generator = cryptoFramework.createAsyKeyGenerator('ECC256');
  const recipientKey = generator.convertKeySync(blob(concatBytes([P256_SPKI_PREFIX, recipient])), null);
  const ephemeral = generator.generateKeyPairSync();
  const agreement = cryptoFramework.createKeyAgreement('ECC256');
  const dh = agreement.generateSecretSync(ephemeral.priKey, recipientKey.pubKey);
  const enc = uncompressedPoint(ephemeral.pubKey.getEncoded().data);
  const secret = sharedSecret(copyBytes(dh.data), enc, recipient);
  const pskHash = labeledExtract(HPKE_SUITE, new Uint8Array(0), 'psk_id_hash', new Uint8Array(0));
  const info = ascii(INFO_TEXT);
  const infoHash = labeledExtract(HPKE_SUITE, new Uint8Array(0), 'info_hash', info);
  const schedule = concatBytes([new Uint8Array([0]), pskHash, infoHash]);
  const secretPrk = labeledExtract(HPKE_SUITE, secret, 'secret', new Uint8Array(0));
  const key = labeledExpand(HPKE_SUITE, secretPrk, 'key', schedule, 32);
  const nonce = labeledExpand(HPKE_SUITE, secretPrk, 'base_nonce', schedule, 12);
  const keyId = bytesToBase64Url(sha256(recipient).subarray(0, 16));
  const ciphertext = sealAes(key, nonce, credentialAad(input, keyId), utf8(plaintext));
  const envelope = new PhoneSecretEnvelope();
  envelope.keyId = keyId;
  envelope.encapsulatedKey = bytesToBase64Url(enc);
  envelope.ciphertext = bytesToBase64Url(ciphertext);
  return envelope;
}
