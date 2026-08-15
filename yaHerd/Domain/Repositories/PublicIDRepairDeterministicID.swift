import Foundation

func publicIDRepairDeterministicReplacementID(
    entityType: PublicIDRepairEntityType,
    originalPublicID: UUID,
    portableRecordIdentity: String,
    attempt: Int = 0
) -> UUID {
    publicIDRepairUUID(
        seed: [
            "yaHerd-public-id-repair-manifest-v1",
            entityType.rawValue,
            originalPublicID.uuidString.lowercased(),
            portableRecordIdentity,
            String(attempt),
        ].joined(separator: "|")
    )
}

/// Migration-only derivation for a pending v3 journal written before the exact cross-Herd
/// replacement mapping was persisted. This preserves the identity that the older repair build
/// would already have assigned, then the migrated manifest makes that result durable.
func publicIDRepairLegacyV3CrossHerdReplacementID(
    entityType: PublicIDRepairEntityType,
    originalPublicID: UUID,
    herdPublicID: UUID
) -> UUID {
    publicIDRepairUUID(
        seed: [
            "yaHerd-public-id-repair-cross-herd-v1",
            entityType.rawValue,
            originalPublicID.uuidString.lowercased(),
            herdPublicID.uuidString.lowercased(),
        ].joined(separator: "|")
    )
}

private func publicIDRepairUUID(seed: String) -> UUID {
    var bytes = Array(publicIDRepairSHA256(Array(seed.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private func publicIDRepairSHA256(_ input: [UInt8]) -> [UInt8] {
    let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    var message = input
    let bitLength = UInt64(message.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 {
        message.append(0)
    }
    for shift in stride(from: 56, through: 0, by: -8) {
        message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
    }

    var h0: UInt32 = 0x6a09e667
    var h1: UInt32 = 0xbb67ae85
    var h2: UInt32 = 0x3c6ef372
    var h3: UInt32 = 0xa54ff53a
    var h4: UInt32 = 0x510e527f
    var h5: UInt32 = 0x9b05688c
    var h6: UInt32 = 0x1f83d9ab
    var h7: UInt32 = 0x5be0cd19

    for blockStart in stride(from: 0, to: message.count, by: 64) {
        var words = Array(repeating: UInt32(0), count: 64)
        for index in 0..<16 {
            let offset = blockStart + index * 4
            words[index] = UInt32(message[offset]) << 24
                | UInt32(message[offset + 1]) << 16
                | UInt32(message[offset + 2]) << 8
                | UInt32(message[offset + 3])
        }
        for index in 16..<64 {
            let s0 = rotateRight(words[index - 15], by: 7)
                ^ rotateRight(words[index - 15], by: 18)
                ^ (words[index - 15] >> 3)
            let s1 = rotateRight(words[index - 2], by: 17)
                ^ rotateRight(words[index - 2], by: 19)
                ^ (words[index - 2] >> 10)
            words[index] = words[index - 16]
                &+ s0
                &+ words[index - 7]
                &+ s1
        }

        var a = h0
        var b = h1
        var c = h2
        var d = h3
        var e = h4
        var f = h5
        var g = h6
        var h = h7

        for index in 0..<64 {
            let sigma1 = rotateRight(e, by: 6)
                ^ rotateRight(e, by: 11)
                ^ rotateRight(e, by: 25)
            let choose = (e & f) ^ ((~e) & g)
            let temp1 = h &+ sigma1 &+ choose &+ constants[index] &+ words[index]
            let sigma0 = rotateRight(a, by: 2)
                ^ rotateRight(a, by: 13)
                ^ rotateRight(a, by: 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = sigma0 &+ majority

            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        h0 &+= a
        h1 &+= b
        h2 &+= c
        h3 &+= d
        h4 &+= e
        h5 &+= f
        h6 &+= g
        h7 &+= h
    }

    var digest: [UInt8] = []
    digest.reserveCapacity(32)
    for word in [h0, h1, h2, h3, h4, h5, h6, h7] {
        digest.append(UInt8((word >> 24) & 0xff))
        digest.append(UInt8((word >> 16) & 0xff))
        digest.append(UInt8((word >> 8) & 0xff))
        digest.append(UInt8(word & 0xff))
    }
    return digest
}

private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
}
