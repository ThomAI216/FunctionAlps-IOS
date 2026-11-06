import Foundation
import Testing
@testable import FunctionAlps

/// The care team (CM OS migration 288): first member, title by locale, photo URL, initials, and the soft failure.
@Suite("Care team")
struct CareTeamTests {
    private let thomas = CareMember(userId: "u1", name: "Thomas Convent", firstName: "Thomas", title: "Coach", titleFr: "Coach", photoPath: "/booking/thomas.webp", isPrimary: true)
    private let alex = CareMember(userId: "u2", name: "Alessandra Ginsburg", firstName: nil, title: "Nutrition expert", titleFr: "Experte en nutrition", photoPath: "https://cdn.example.org/a.webp")

    @Test func firstMemberIsTheFirstRowAndNamesTheTeam() {
        let team = CareTeam(members: [thomas, alex])
        #expect(team.first == thomas)
        #expect(team.firstName == "Thomas")
        #expect(CareTeam.empty.firstName == nil)
        #expect(CareTeam.empty.isEmpty)
    }

    @Test func firstNameFallsBackToTheFirstWordOfTheName() {
        #expect(CareTeamLogic.firstName(alex) == "Alessandra")
        #expect(CareTeamLogic.firstName(CareMember(userId: "x", name: "  Marie Curie ", firstName: "  "))  == "Marie")
    }

    @Test func titleFollowsTheAppLanguageAndFallsBack() {
        #expect(CareTeamLogic.title(alex, french: false) == "Nutrition expert")
        #expect(CareTeamLogic.title(alex, french: true) == "Experte en nutrition")
        let noFr = CareMember(userId: "x", name: "A B", title: "Coach", titleFr: " ")
        #expect(CareTeamLogic.title(noFr, french: true) == "Coach")
        #expect(CareTeamLogic.title(CareMember(userId: "x", name: "A B"), french: false) == nil)
        #expect(CareTeamLogic.isFrench("fr") && CareTeamLogic.isFrench("fr-CH") && !CareTeamLogic.isFrench("en") && !CareTeamLogic.isFrench(nil))
    }

    @Test func photoPathIsPrefixedAndAbsoluteUrlsAreKept() {
        #expect(CareTeamLogic.photoURL("/booking/thomas.webp")?.absoluteString == "https://dashboard.functionalps.ch/booking/thomas.webp")
        #expect(CareTeamLogic.photoURL("booking/alex.webp")?.absoluteString == "https://dashboard.functionalps.ch/booking/alex.webp")
        #expect(CareTeamLogic.photoURL("https://cdn.example.org/a.webp")?.absoluteString == "https://cdn.example.org/a.webp")
        #expect(CareTeamLogic.photoURL(nil) == nil)
        #expect(CareTeamLogic.photoURL("  ") == nil)
    }

    @Test func initialsAreFirstAndLastWord() {
        #expect(CareTeamLogic.initials("Thomas Convent") == "TC")
        #expect(CareTeamLogic.initials("alessandra") == "A")
        #expect(CareTeamLogic.initials("Jean-Pierre de la Fontaine") == "JF")
        #expect(CareTeamLogic.initials("  ") == "")
    }

    @Test func rpcRowsDecodeFromSnakeCase() throws {
        let json = #"[{"user_id":"u1","name":"Thomas Convent","first_name":"Thomas","title":"Coach","title_fr":null,"photo_path":"/booking/thomas.webp","assignment_type":"coach","is_primary":true}]"#
        let rows = try JSON.decode([CareMember].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].userId == "u1" && rows[0].titleFr == nil && rows[0].isPrimary == true)
    }

    @Test func theServiceFailsSoftToAnEmptyTeam() async {
        let backend = StubBackend()
        backend.careTeamFails = true
        let service = MessagingService(backend: backend)
        #expect(await service.careTeam().isEmpty)
        backend.careTeamFails = false
        backend.careTeamResult = [thomas]
        #expect(await service.careTeam().firstName == "Thomas")
    }
}
