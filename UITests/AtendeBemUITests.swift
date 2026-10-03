import XCTest

final class AtendeBemUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndPresentsAnInteractiveScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.firstMatch.exists || app.textFields.firstMatch.exists || app.secureTextFields.firstMatch.exists)
    }

    @MainActor
    func testSignInRequiresCredentialsWhenSignedOut() throws {
        let app = XCUIApplication()
        app.launch()
        let email = app.textFields["login.email"]
        guard email.waitForExistence(timeout: 10) else { throw XCTSkip("A sessão existente é preservada; teste requer aparelho sem login.") }
        XCTAssertFalse(app.buttons["login.submit"].isEnabled)
        email.tap()
        email.typeText("homologacao@example.invalid")
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "E-mail sozinho não autoriza entrar.")
    }

    @MainActor
    func testPrivacyAccessibleBeforeAuthentication() throws {
        let app = XCUIApplication()
        app.launch()
        guard app.textFields["login.email"].waitForExistence(timeout: 10) else { throw XCTSkip("A sessão existente é preservada.") }
        let privacy = app.buttons["Privacidade e suporte"]
        if !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        XCTAssertTrue(app.staticTexts["Seus dados no aplicativo"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testHomeShortcutsOpenTheirOwnDestination() throws {
        let app = XCUIApplication()
        for (identifier, title) in [("home.prescription", "Receitas"), ("home.exams", "Exames"), ("home.consultation", "Consulta"), ("home.lari", "LARI")] {
            app.launch()
            let shortcut = app.buttons[identifier]
            guard shortcut.waitForExistence(timeout: 10) else {
                throw XCTSkip("Requer sessão de homologação com perfil clínico e quatro atalhos visíveis. Não modifica login nem preferências.")
            }
            shortcut.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "O atalho \(identifier) deve abrir \(title).")
            if identifier != "home.lari" { XCTAssertFalse(app.navigationBars["LARI"].exists) }
            app.terminate()
        }
    }

    @MainActor
    func testAgendaDayAndListHaveDifferentPresentations() throws {
        let app = XCUIApplication()
        app.launch()
        guard app.tabBars.buttons["Agenda"].waitForExistence(timeout: 10) else { throw XCTSkip("Requer sessão de homologação com Agenda habilitada.") }
        app.tabBars.buttons["Agenda"].tap()
        let selector = app.segmentedControls["agenda.displayMode"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        selector.buttons["Lista"].tap()
        XCTAssertTrue(app.staticTexts["Lista compacta dos agendamentos do dia selecionado. Horários em UTC−03:00."].exists)
        selector.buttons["Dia"].tap()
        XCTAssertTrue(app.staticTexts["Linha do tempo do dia, por hora. Horários em UTC−03:00."].exists)
    }
}
