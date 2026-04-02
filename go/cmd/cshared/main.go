package main

/*
#include <stdlib.h>

typedef void (*neo_stream_cb)(const char* text, int is_last);

static inline void neo_invoke_stream_cb(neo_stream_cb cb, const char* t, int is_last) {
	if (cb != NULL) {
		cb(t, is_last);
	}
}
*/
import "C"
import (
	"unsafe"

	"github.com/absgrafx/nodeneo/mobile"
)

// freeWith is a helper the Dart side must call to free returned strings.
//
//export FreeString
func FreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// --- Lifecycle ---

//export Init
func Init(dataDir, ethNodeURL *C.char, chainID C.longlong, diamondAddr, morTokenAddr, blockscoutURL *C.char) *C.char {
	result := mobile.Init(
		C.GoString(dataDir),
		C.GoString(ethNodeURL),
		int64(chainID),
		C.GoString(diamondAddr),
		C.GoString(morTokenAddr),
		C.GoString(blockscoutURL),
	)
	return C.CString(result)
}

//export Shutdown
func Shutdown() {
	mobile.Shutdown()
}

//export IsReady
func IsReady() C.int {
	if mobile.IsReady() {
		return 1
	}
	return 0
}

// --- Logging ---

//export GetLogDir
func GetLogDir() *C.char {
	return C.CString(mobile.GetLogDir())
}

//export SetLogLevel
func SetLogLevel(level *C.char) *C.char {
	return C.CString(mobile.SetLogLevel(C.GoString(level)))
}

//export GetLogLevel
func GetLogLevel() *C.char {
	return C.CString(mobile.GetLogLevel())
}

//export AppLog
func AppLog(level, message *C.char) {
	mobile.AppLog(C.GoString(level), C.GoString(message))
}

//export GetProxyRouterVersion
func GetProxyRouterVersion() *C.char {
	return C.CString(mobile.GetProxyRouterVersion())
}

// --- Encryption ---

//export SetEncryptionKey
func SetEncryptionKey(keyHex *C.char) *C.char {
	return C.CString(mobile.SetEncryptionKey(C.GoString(keyHex)))
}

// --- Wallet ---

//export CreateWallet
func CreateWallet() *C.char {
	return C.CString(mobile.CreateWallet())
}

//export ImportWalletMnemonic
func ImportWalletMnemonic(mnemonic *C.char) *C.char {
	return C.CString(mobile.ImportWalletMnemonic(C.GoString(mnemonic)))
}

//export ImportWalletPrivateKey
func ImportWalletPrivateKey(hexKey *C.char) *C.char {
	return C.CString(mobile.ImportWalletPrivateKey(C.GoString(hexKey)))
}

//export ExportPrivateKey
func ExportPrivateKey() *C.char {
	return C.CString(mobile.ExportPrivateKey())
}

//export GetWalletSummary
func GetWalletSummary() *C.char {
	return C.CString(mobile.GetWalletSummary())
}

//export VerifyRecoveryMnemonic
func VerifyRecoveryMnemonic(mnemonic *C.char) *C.char {
	return C.CString(mobile.VerifyRecoveryMnemonic(C.GoString(mnemonic)))
}

//export VerifyRecoveryPrivateKey
func VerifyRecoveryPrivateKey(hexKey *C.char) *C.char {
	return C.CString(mobile.VerifyRecoveryPrivateKey(C.GoString(hexKey)))
}

//export SendETH
func SendETH(toAddr, amountWei *C.char) *C.char {
	return C.CString(mobile.SendETH(C.GoString(toAddr), C.GoString(amountWei)))
}

//export SendMOR
func SendMOR(toAddr, amountWei *C.char) *C.char {
	return C.CString(mobile.SendMOR(C.GoString(toAddr), C.GoString(amountWei)))
}

// --- Models ---

//export GetActiveModels
func GetActiveModels(teeOnly C.int) *C.char {
	return C.CString(mobile.GetActiveModels(teeOnly != 0))
}

//export GetRatedBids
func GetRatedBids(modelID *C.char) *C.char {
	return C.CString(mobile.GetRatedBids(C.GoString(modelID)))
}

//export ReusableSessionForModel
func ReusableSessionForModel(modelID *C.char) *C.char {
	return C.CString(mobile.ReusableSessionForModel(C.GoString(modelID)))
}

//export EstimateOpenSessionStake
func EstimateOpenSessionStake(modelID *C.char, durationSeconds C.longlong, directPayment C.int) *C.char {
	return C.CString(mobile.EstimateOpenSessionStake(C.GoString(modelID), int64(durationSeconds), directPayment != 0))
}

// --- Sessions ---

//export OpenSession
func OpenSession(modelID *C.char, durationSeconds C.longlong, directPayment C.int) *C.char {
	return C.CString(mobile.OpenSession(C.GoString(modelID), int64(durationSeconds), directPayment != 0))
}

//export CloseSession
func CloseSession(sessionID *C.char) *C.char {
	return C.CString(mobile.CloseSession(C.GoString(sessionID)))
}

//export GetSession
func GetSession(sessionID *C.char) *C.char {
	return C.CString(mobile.GetSession(C.GoString(sessionID)))
}

//export GetUnclosedUserSessions
func GetUnclosedUserSessions() *C.char {
	return C.CString(mobile.GetUnclosedUserSessions())
}

// --- Chat ---

//export SendPrompt
func SendPrompt(sessionID, conversationID, prompt *C.char, stream C.int) *C.char {
	return C.CString(mobile.SendPrompt(
		C.GoString(sessionID),
		C.GoString(conversationID),
		C.GoString(prompt),
		stream != 0,
	))
}

// SendPromptStream runs the same path as SendPrompt but forwards each streamed delta to [cb]
// before returning the final JSON (including "response" with the full text).
// [cb] may be NULL (no per-chunk delivery).
//
//export SendPromptStream
func SendPromptStream(sessionID, conversationID, prompt *C.char, stream C.int, cb C.neo_stream_cb) *C.char {
	chunk := func(text string, last bool) error {
		if cb == nil {
			return nil
		}
		ct := C.CString(text)
		var lastInt C.int
		if last {
			lastInt = 1
		}
		C.neo_invoke_stream_cb(cb, ct, lastInt)
		C.free(unsafe.Pointer(ct))
		return nil
	}
	out := mobile.SendPromptWithStreamCallback(
		C.GoString(sessionID),
		C.GoString(conversationID),
		C.GoString(prompt),
		stream != 0,
		chunk,
	)
	return C.CString(out)
}

// --- Conversations ---

//export ClaimEmptyDraftForModel
func ClaimEmptyDraftForModel(modelID, modelName, provider *C.char, isTEE C.int) *C.char {
	return C.CString(mobile.ClaimEmptyDraftForModel(
		C.GoString(modelID),
		C.GoString(modelName),
		C.GoString(provider),
		isTEE != 0,
	))
}

//export CreateConversation
func CreateConversation(convID, modelID, modelName, provider *C.char, isTEE C.int) *C.char {
	return C.CString(mobile.CreateConversation(
		C.GoString(convID),
		C.GoString(modelID),
		C.GoString(modelName),
		C.GoString(provider),
		isTEE != 0,
	))
}

//export SetConversationSession
func SetConversationSession(conversationID, sessionID *C.char) *C.char {
	return C.CString(mobile.SetConversationSession(
		C.GoString(conversationID),
		C.GoString(sessionID),
	))
}

//export SetConversationTitle
func SetConversationTitle(conversationID, title *C.char) *C.char {
	return C.CString(mobile.SetConversationTitle(
		C.GoString(conversationID),
		C.GoString(title),
	))
}

//export SetConversationPinned
func SetConversationPinned(conversationID *C.char, pinned C.int) *C.char {
	return C.CString(mobile.SetConversationPinned(C.GoString(conversationID), pinned != 0))
}

//export DeleteConversation
func DeleteConversation(conversationID *C.char) *C.char {
	return C.CString(mobile.DeleteConversation(C.GoString(conversationID)))
}

//export GetConversations
func GetConversations() *C.char {
	return C.CString(mobile.GetConversations())
}

//export GetMessages
func GetMessages(conversationID *C.char) *C.char {
	return C.CString(mobile.GetMessages(C.GoString(conversationID)))
}

// --- Preferences ---

//export SetPreference
func SetPreference(key, value *C.char) *C.char {
	return C.CString(mobile.SetPreference(C.GoString(key), C.GoString(value)))
}

//export GetPreference
func GetPreference(key *C.char) *C.char {
	return C.CString(mobile.GetPreference(C.GoString(key)))
}

// --- Expert Mode (native proxy-router swagger API) ---

//export StartExpertAPI
func StartExpertAPI(address, publicURL *C.char) *C.char {
	return C.CString(mobile.StartExpertAPI(C.GoString(address), C.GoString(publicURL)))
}

//export StopExpertAPI
func StopExpertAPI() *C.char {
	return C.CString(mobile.StopExpertAPI())
}

//export ExpertAPIStatus
func ExpertAPIStatus() *C.char {
	return C.CString(mobile.ExpertAPIStatus())
}

func main() {}
