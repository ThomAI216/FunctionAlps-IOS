import Testing
@testable import FunctionAlps

@Suite("EmailNormalizer (must match the Expo app + canonical_email)")
struct EmailNormalizerTests {
    @Test func lowercasesAndTrims() { #expect(EmailNormalizer.normalize("  Alex@Example.COM ") == "alex@example.com") }
    @Test func stripsPlusAliasEverywhere() { #expect(EmailNormalizer.normalize("user+app@example.com") == "user@example.com") }
    @Test func stripsGmailDotsAndFoldsGooglemail() {
        #expect(EmailNormalizer.normalize("thomas.convent.216@gmail.com") == "thomasconvent216@gmail.com")
        #expect(EmailNormalizer.normalize("a.b+x@googlemail.com") == "ab@gmail.com")
    }
    @Test func leavesNonEmailsAlone() {
        #expect(EmailNormalizer.normalize("notanemail") == "notanemail")
        #expect(EmailNormalizer.normalize("x@") == "x@")
        #expect(EmailNormalizer.normalize("@x") == "@x")
    }
}
