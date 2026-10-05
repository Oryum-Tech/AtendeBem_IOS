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
        if app.textFields["login.email"].waitForExistence(timeout: 5) {
            attachScreen(app, named: "entrada-sem-autenticacao")
        }
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
        attachScreen(app, named: "privacidade-antes-do-login")
    }

    @MainActor
    func testRegistrationAccessibleBeforeAuthenticationWithoutCreatingAnAccount() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        guard app.textFields["login.email"].waitForExistence(timeout: 10) else {
            throw XCTSkip("A sessão existente é preservada; não capturar dados autenticados.")
        }
        let discover = app.buttons["login.discoverAtendeBem"]
        for _ in 0..<6 {
            if discover.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(discover.isHittable, "O cadastro deve estar acessível antes do login.")
        discover.tap()
        XCTAssertTrue(app.navigationBars["Conheça o AtendeBem"].waitForExistence(timeout: 10))
        attachScreen(app, named: "apresentacao-do-aplicativo-sem-dados")
        let createAccount = app.buttons["welcome.createAccount"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 5))
        XCTAssertTrue(createAccount.isHittable, "A ação de criar conta deve estar acessível ao toque.")
        createAccount.tap()
        XCTAssertTrue(app.navigationBars["Criar conta"].waitForExistence(timeout: 10))
        let clinicName = app.textFields["registration.clinicName"]
        XCTAssertTrue(clinicName.waitForExistence(timeout: 10), "O cadastro deve apresentar o campo da clínica.")
        attachScreen(app, named: "apresentacao-do-cadastro-sem-dados")
        let form = [
            app.collectionViews.containing(.textField, identifier: "registration.clinicName").firstMatch,
            app.tables.containing(.textField, identifier: "registration.clinicName").firstMatch,
            app.scrollViews.containing(.textField, identifier: "registration.clinicName").firstMatch
        ].first(where: { $0.exists })
        for identifier in ["registration.clinicName", "registration.name", "registration.email"] {
            let field = app.textFields[identifier]
            for _ in 0..<6 {
                if field.isHittable { break }
                guard let form else { break }
                form.swipeUp()
            }
            XCTAssertTrue(field.isHittable, "O campo \(identifier) deve manter seu identificador e ser acessível no formulário.")
        }
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
