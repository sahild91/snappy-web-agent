use std::fs;
use crate::models::*;
fn load_key_from_cargo_toml() -> Result<[u32; 8], Box<dyn std::error::Error>> {
    let cargo_content = fs::read_to_string("Cargo.toml")?;
    let cargo_toml: CargoToml = toml::from_str(&cargo_content)?;

    if let Some(metadata) = cargo_toml.package.metadata {
        if let Some(encryption) = metadata.encryption {
            if encryption.key.len() == 8 {
                let mut key_array = [0u32; 8];
                key_array.copy_from_slice(&encryption.key);
                return Ok(key_array);
            }
        }
    }

    // Fallback to default key if not found in Cargo.toml
    Ok([
        0x9c2f6d44, 0xa68b3179, 0xf2c1be0a, 0x7d54c3f1, 0x3e118d6b, 0x4f0b92e7, 0x1dac785c, 0xe6132fa8,
    ])
}

const CHACHA20_BLOCK_SIZE: usize = 64;

fn chacha20_quarter_round(state: &mut [u32; 16], a: usize, b: usize, c: usize, d: usize) {
    state[a] = state[a].wrapping_add(state[b]);
    state[d] ^= state[a];
    state[d] = state[d].rotate_left(16);

    state[c] = state[c].wrapping_add(state[d]);
    state[b] ^= state[c];
    state[b] = state[b].rotate_left(12);

    state[a] = state[a].wrapping_add(state[b]);
    state[d] ^= state[a];
    state[d] = state[d].rotate_left(8);

    state[c] = state[c].wrapping_add(state[d]);
    state[b] ^= state[c];
    state[b] = state[b].rotate_left(7);
}

fn chacha20_block(state: &[u32; 16], output: &mut [u8; CHACHA20_BLOCK_SIZE]) {
    let mut working_state = *state;

    for _ in 0..10 {
        chacha20_quarter_round(&mut working_state, 0, 4, 8, 12);
        chacha20_quarter_round(&mut working_state, 1, 5, 9, 13);
        chacha20_quarter_round(&mut working_state, 2, 6, 10, 14);
        chacha20_quarter_round(&mut working_state, 3, 7, 11, 15);
        chacha20_quarter_round(&mut working_state, 0, 5, 10, 15);
        chacha20_quarter_round(&mut working_state, 1, 6, 11, 12);
        chacha20_quarter_round(&mut working_state, 2, 7, 8, 13);
        chacha20_quarter_round(&mut working_state, 3, 4, 9, 14);
    }

    for i in 0..16 {
        let word = working_state[i].wrapping_add(state[i]);
        output[i * 4..(i + 1) * 4].copy_from_slice(&word.to_le_bytes());
    }
}

pub fn chacha20_encrypt(
    key: &[u8; 32],
    nonce: &[u8; 32],
    counter: u32,
    input: &[u8],
    output: &mut [u8]
) {
    let mut state = [
        0x61707865,
        0x3320646e,
        0x79622d32,
        0x6b206574,
        u32::from_le_bytes([key[0], key[1], key[2], key[3]]),
        u32::from_le_bytes([key[4], key[5], key[6], key[7]]),
        u32::from_le_bytes([key[8], key[9], key[10], key[11]]),
        u32::from_le_bytes([key[12], key[13], key[14], key[15]]),
        u32::from_le_bytes([key[16], key[17], key[18], key[19]]),
        u32::from_le_bytes([key[20], key[21], key[22], key[23]]),
        u32::from_le_bytes([key[24], key[25], key[26], key[27]]),
        u32::from_le_bytes([key[28], key[29], key[30], key[31]]),
        counter,
        u32::from_le_bytes([nonce[0], nonce[1], nonce[2], nonce[3]]),
        u32::from_le_bytes([nonce[4], nonce[5], nonce[6], nonce[7]]),
        u32::from_le_bytes([nonce[8], nonce[9], nonce[10], nonce[11]]),
    ];

    let mut keystream = [0u8; CHACHA20_BLOCK_SIZE];
    let mut i = 0;

    assert_eq!(input.len(), output.len(), "Input and output buffers must be the same length");

    while i < input.len() {
        chacha20_block(&state, &mut keystream);
        state[12] = state[12].wrapping_add(1);

        for (keystream_byte, _) in keystream.iter().take(CHACHA20_BLOCK_SIZE).enumerate() {
            if i < input.len() {
                output[i] = input[i] ^ keystream[keystream_byte];
                i += 1;
            } else {
                break;
            }
        }
    }
}

const MAGIC1: u32 = 0x9e3779b9;
const MAGIC2: u32 = 0x85ebca6b;
const MAGIC3: u32 = 0xc2b2ae35;

fn r(x: &mut u32, y: u32) {
    *x ^= y.wrapping_add(MAGIC1).wrapping_mul(*x | MAGIC2);
    *x = x.rotate_left(13).wrapping_mul(MAGIC3);
}

fn w(h: &mut [u8], x: u32, i: usize) {
    let bytes = x.to_le_bytes();
    h[i * 4..(i + 1) * 4].copy_from_slice(&bytes);
}

pub fn hash_serial(b: &[u8], h: &mut [u8; 32]) {
    let v: [u32; 8] = load_key_from_cargo_toml().unwrap_or([
        0x9c2f6d44, 0xa68b3179, 0xf2c1be0a, 0x7d54c3f1, 0x3e118d6b, 0x4f0b92e7, 0x1dac785c, 0xe6132fa8,
    ]);
    let mut v = v;

    for i in 0..b.len() {
        r(&mut v[i % 8], (b[i] as u32) + (i as u32));
    }

    for i in 0..8 {
        w(h, v[(i * 5) % 8], i);
    }
}
pub fn chacha20_decrypt(key: &[u8; 32], counter: u32, ciphertext: &[u8], plaintext: &mut [u8]) {
    // ChaCha20 is a symmetric stream cipher, so encryption and decryption are identical operations
    chacha20_encrypt(key, key, counter, ciphertext, plaintext);
}
