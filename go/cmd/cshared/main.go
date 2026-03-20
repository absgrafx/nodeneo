package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"unsafe"

	"github.com/absgrafx/redpill/mobile"
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

// --- Conversations ---

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

func main() {}
