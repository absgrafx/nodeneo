# Node Neo Terms of Use

**Effective date:** May 1, 2026  
**Last updated:** May 1, 2026  
**Publisher:** absgrafx ([github.com/absgrafx](https://github.com/absgrafx))  
**App:** Node Neo (`com.absgrafx.nodeneo`) — iOS, macOS, Android

> **Plain English summary:** Node Neo is a free, open-source app that lets you chat with AI models on a decentralized network. You hold your own wallet keys; if you lose them, we cannot help you recover them. The AI models are operated by independent third parties; their responses are theirs, not ours. The app is provided as-is. You're responsible for using it lawfully.

These Terms of Use ("Terms") form a binding agreement between you ("you") and **absgrafx**, an independent publisher (referred to as "we", "us", or "absgrafx"). By installing, launching, or using Node Neo (the "App"), you agree to these Terms and to the [Privacy Policy](./PRIVACY.md). If you do not agree, do not install or use the App.

---

## 1. What Node Neo is — and isn't

Node Neo is a **client application** for the [Morpheus](https://mor.org) decentralized AI inference network. The App lets you:

- Hold a self-custodial cryptocurrency wallet on your device for paying for AI inference sessions
- Discover AI models published to the Morpheus on-chain registry
- Open paid sessions with independent providers and chat with their models

Node Neo is **not**:

- An AI model. We do not operate, train, or host any AI models. The App connects you to third-party providers.
- A custodial wallet, broker, exchange, or money-transmission service. absgrafx never holds your wallet keys, your funds, or your transactions. Everything happens on your device or on the public Base blockchain.
- Investment, financial, legal, or tax advice. Nothing in the App is a recommendation to buy, sell, or hold any cryptocurrency, including MOR or ETH.
- A guarantee of AI accuracy. AI-generated content is often wrong, occasionally harmful, and never authoritative.

---

## 2. Eligibility

You must be at least **17 years old** (Apple's age rating for the App) and legally able to enter into binding contracts under the laws of your jurisdiction. Don't use Node Neo if doing so is restricted where you live (see §11 — Jurisdictional restrictions).

If you're using the App on behalf of an organization, you represent that you have authority to bind that organization to these Terms. (Otherwise, you're using it as an individual.)

---

## 3. Your wallet, your responsibility

Node Neo creates or imports a **self-custodial cryptocurrency wallet** that lives entirely on your device. This is a feature, not a bug — but it means:

- **Your private key is the only thing that controls your wallet.** Whoever holds the key controls the funds, the AI inference sessions, and any other on-chain action attributed to that wallet.
- **absgrafx has no copy of your private key, your password, or your data.** We physically cannot recover your wallet if you lose access. There is no "forgot password" link that gives you back your funds.
- **Back up your private key.** Use the in-app *Wallet → Export private key* function and store the backup somewhere secure (a hardware password manager, a paper backup in a safe — anywhere except cloud-synced plain text).
- **You are responsible for the security of your device.** A device compromised by malware, an unlocked stolen phone, or a screen-shoulder of your private key during export can lead to total loss of funds.
- **Transactions on Base are irreversible.** A typo in a recipient address means the funds are gone. There is no chargeback mechanism.

If any of this is unfamiliar territory, we recommend reading [Ethereum.org's introduction to wallets](https://ethereum.org/en/wallets/) before holding any meaningful amount of value in Node Neo.

---

## 4. AI providers and content

When you start a chat session, Node Neo connects you to an **independent third-party AI provider** advertised on the Morpheus on-chain registry. absgrafx has no business relationship with these providers, does not vet them, and does not control or moderate their output.

By using a chat session, you understand that:

- **The provider — not absgrafx — is the entity that processes your prompts and generates responses.** absgrafx never sees, logs, or relays your chat content. The provider's data-handling practices are governed by the provider's own terms.
- **AI responses can be wrong, biased, offensive, defamatory, or dangerous.** Treat AI output as a starting point, not a source of truth. Never act on AI-generated medical, legal, financial, or safety advice without independent verification by a qualified human.
- **Some providers operate inside Trusted Execution Environments (TEEs)** — these appear with the "MAX Privacy" badge in the model picker. With a MAX Privacy provider, your prompts are encrypted such that even the provider operator cannot read them in clear text. **For any conversation involving sensitive content, only use MAX Privacy models.** Non-TEE providers can read, log, and retain your prompts.
- **Providers may go offline mid-session** without warning. The on-chain session payment is locked into the contract's escrow during the session window; refund mechanics are governed by the Morpheus protocol, not by absgrafx.

absgrafx **does not** moderate, edit, censor, or take responsibility for AI-generated content. We have no ability to delete, redact, or recall a response after the provider has emitted it.

---

## 5. Acceptable use

You agree **not** to use Node Neo to:

- Violate any law in your jurisdiction or in the jurisdiction of any provider you connect to
- Generate or disseminate content depicting child sexual abuse material (CSAM); credible threats of violence; non-consensual intimate imagery; instructions for synthesizing weapons of mass destruction; or other content prohibited by Apple's [App Store Review Guideline 1.1](https://developer.apple.com/app-store/review/guidelines/#objectionable-content)
- Attempt to exploit, deceive, or harass AI providers or other users of the Morpheus network (e.g., session payment fraud, prompt-injection of system-level commands designed to compromise provider infrastructure)
- Reverse-engineer, decompile, or attempt to extract proprietary content from the App's binary, except to the extent expressly permitted by the open-source license under which the App is published (MIT) or by applicable law (e.g., interoperability research in EU jurisdictions)
- Use automated scripts, bots, or scraping tools that would overload providers, the Morpheus registry, or the Base blockchain
- Misrepresent your identity, agency, or affiliation with absgrafx (impersonation), or use the App's name, logo, or branding in a way that suggests we endorse something we don't

We may update this list of prohibited uses if circumstances require it. Continued use of the App after such an update constitutes acceptance.

---

## 6. Open source license

Node Neo's source code is published under the **MIT License**. See [`LICENSE`](./LICENSE) in the repository for the full text. In short: you may use, copy, modify, and redistribute the source code, including for commercial purposes, provided you retain the copyright notice and the MIT License text.

These Terms govern your use of the **App as distributed by absgrafx through the Apple App Store, Google Play, or our official channels.** They do not extend to your use of forks, derivative works, or self-built versions of the source code — those are governed by the MIT License alone.

---

## 7. Updates and availability

We may update the App at any time to add features, fix bugs, change behavior, or comply with law or platform requirements. Some updates may be required to continue using the App.

We do not guarantee continuous availability. The App, the Morpheus protocol, the Base blockchain, the model registry, and individual AI providers are all separate systems that may be unavailable, slow, or behave unexpectedly at any time. None of this is our fault.

We may discontinue Node Neo at any time. If we do, the open-source code remains available under MIT and you can continue to build and use it yourself.

---

## 8. Disclaimers

THE APP IS PROVIDED **"AS IS" AND "AS AVAILABLE"**, WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, ACCURACY, COMPLETENESS, OR UNINTERRUPTED OPERATION.

Without limiting the above, absgrafx specifically disclaims:

- Any warranty that the App is free of bugs, security vulnerabilities, or compatibility issues
- Any warranty about the accuracy, safety, or appropriateness of AI-generated content
- Any warranty about the availability, performance, or solvency of AI providers, the Morpheus protocol, or the Base blockchain
- Any warranty that wallet operations will be successful, timely, or recoverable in the event of error, network failure, or user mistake
- Any warranty that the price of MOR, ETH, or any other token will hold its value

You acknowledge that you use the App at your own risk.

---

## 9. Limitation of liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, **absgrafx (and its affiliates, contractors, and contributors) WILL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, REVENUE, DATA, GOODWILL, OR CRYPTOCURRENCY**, arising out of or in connection with your use of (or inability to use) the App, even if we have been advised of the possibility of such damages.

In jurisdictions that do not allow the exclusion or limitation of certain damages, our total liability to you for all claims arising from or relating to the App is limited to **the greater of (a) the amount you paid absgrafx for the App in the 12 months preceding the claim, which is currently zero (the App is free), or (b) one hundred U.S. dollars (US $100)**.

This limitation applies regardless of the legal theory under which the claim is brought (contract, tort, statute, or otherwise) and survives termination of these Terms.

---

## 10. Indemnification

You agree to indemnify and hold absgrafx harmless from any claim, loss, liability, expense, or demand (including reasonable legal fees) arising out of:

- Your use of the App in violation of these Terms or applicable law
- Your interaction with any third-party AI provider, including content you generate, prompts you submit, or how you act on responses you receive
- Your loss of access to your wallet, your private key, or your funds, regardless of cause

This obligation survives termination of these Terms.

---

## 11. Jurisdictional restrictions

You may not use Node Neo if you are located in, or are a resident or national of, any country or region where:

- Use of decentralized AI services or self-custodial cryptocurrency wallets is prohibited by law
- absgrafx is prohibited from providing software by U.S. or other applicable export controls (currently including, but not limited to: jurisdictions designated as "embargoed" by the U.S. Office of Foreign Assets Control — Cuba, Iran, North Korea, Syria, the Crimea, Donetsk, and Luhansk regions of Ukraine, and the territory governed by the Russian Federation as of the App's distribution date, subject to change)

You are responsible for knowing the law of your jurisdiction. Distribution through the Apple App Store may further restrict availability based on Apple's country / region policies, which are outside absgrafx's control.

---

## 12. Termination

You can stop using Node Neo at any time by uninstalling it. Your wallet and on-chain assets remain on the Base blockchain regardless — uninstalling the App does not erase or transfer them.

We can terminate or suspend your access to the App, or stop publishing new versions, at any time and for any reason. Termination of these Terms does not affect:

- Your rights under the MIT License to the source code
- Your wallet, your funds, or your on-chain history (we have no power over those)
- Sections of these Terms that are explicitly intended to survive termination (Disclaimers, Limitation of Liability, Indemnification, Governing Law, and this section)

---

## 13. Governing law and dispute resolution

These Terms are governed by the laws of the **State of South Dakota**, United States, without regard to its conflict-of-laws provisions.

Any dispute arising from or relating to these Terms or the App will be brought in the state or federal courts located in **South Dakota**, and you consent to personal jurisdiction in those courts. Both parties waive any objection based on inconvenient forum.

**No class actions.** To the extent permitted by law, any dispute will be brought on an individual basis only, and not as a plaintiff or class member in any purported class, consolidated, or representative proceeding.

If you are a consumer in the EU / EEA / UK and the consumer protection laws of your country grant you mandatory rights that conflict with the above, those mandatory rights apply notwithstanding this section.

---

## 14. Changes to these Terms

We may update these Terms when material aspects of the App change (e.g., adding a new permission, integrating a new third party, expanding to new platforms). We'll:

- Update the "Last updated" date at the top of this document
- Note material changes in the next release's `RELEASE_NOTES.md` and the in-app *About* screen
- For changes that materially expand your obligations or reduce your rights, give at least 30 days notice through the App and on `https://nodeneo.ai/terms` before the change takes effect

The current and historical versions of these Terms live in this repository's git history.

---

## 15. Miscellaneous

- **Severability:** If any provision of these Terms is held unenforceable, the remaining provisions remain in full effect.
- **No waiver:** Our failure to enforce any provision is not a waiver of our right to enforce it later.
- **Entire agreement:** These Terms, together with the [Privacy Policy](./PRIVACY.md) and the [`LICENSE`](./LICENSE), are the complete agreement between you and absgrafx regarding the App.
- **Assignment:** You may not assign these Terms. We may assign them in connection with a transfer of the App or a corporate restructuring.
- **Headings:** Section titles are for convenience and do not affect interpretation.

---

## 16. Contact

| For | Reach us at |
|---|---|
| Bug reports, feature requests, support | <https://github.com/absgrafx/nodeneo/issues> |
| Anything else (questions about these Terms, privacy, security, general) | `nodeneo@absgrafx.com` |

absgrafx is an independent publisher. The contact address above is a single shared inbox; please put a clear subject line (e.g. *"Terms question"*, *"Security disclosure"*) so we can prioritize correctly. We do not run an organization-scale legal team; please be patient and detailed in your communications.
