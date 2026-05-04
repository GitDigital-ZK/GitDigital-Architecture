module identity

import crypto.sha256
import encoding.base64

// Struct to represent the masked identity
struct MaskedIdentity {
pub:
	gh_id_hash    string
	session_nonce string
}

// mask_identity creates a local hash of the GitHub ID to ensure 
// the raw ID is never stored in the ZK-Registry.
pub fn mask_identity(raw_github_id string, salt string) MaskedIdentity {
	// Combine ID with a local salt for privacy
	combined := raw_github_id + salt
	
	// Use V's native crypto to hash
	id_hash := sha256.sum(combined.bytes()).hex()
	
	// Generate a simple session nonce
	nonce := base64.encode(salt.bytes())

	return MaskedIdentity{
		gh_id_hash:    id_hash
		session_nonce: nonce
	}
}

fn main() {
	// Example usage on the Android device
	user_id := 'gitdigital-zk-user-123'
	local_salt := 'device-specific-entropy'
	
	masked := mask_identity(user_id, local_salt)
	println('Masked ID: ${masked.gh_id_hash}')
}
