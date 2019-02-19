import Vapor
import Imperial
import Authentication

struct ImperialController: RouteCollection {
    func boot(router: Router) throws {
        guard let callbackURL = Environment.get("GOOGLE_CALLBACK_URL") else {
            fatalError("Callback URL not set")
        }
        try router.oAuth(from: Google.self, authenticate: "login-google", callback: callbackURL, scope: ["profile", "email"], completion: processGoogleLogin)
    }
    
    func processGoogleLogin(request: Request, token: String) throws -> Future<ResponseEncodable> {
        return try Google.getUser(on: request).flatMap(to: ResponseEncodable.self) { userInfo in
            return User.query(on: request).filter(\.username == userInfo.email).first().flatMap(to: ResponseEncodable.self) { foundUser in
                guard let existingUser = foundUser else {
                    let user = User(name: userInfo.name, username: userInfo.email, password: "")
                    return user.save(on: request).map(to: ResponseEncodable.self) { user in
                        return request.redirect(to: "/")
                    }
                }
                try request.authenticateSession(existingUser)
                return request.future(request.redirect(to: "/"))
            }
        }
    }
}

struct GoogleUserInfo: Content{
    let email: String
    let name: String
}

extension Google {
    static func getUser(on request: Request) throws -> Future<GoogleUserInfo> {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = try BearerAuthorization(token: request.accessToken())
        
        let googleAPIURL = "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"
        
        return try request.client().get(googleAPIURL, headers: headers).map(to: GoogleUserInfo.self) { response in
            guard response.http.status == .ok else {
                if response.http.status == .unauthorized {
                    throw Abort.redirect(to: "/login-google")
                } else {
                    throw Abort(.internalServerError)
                }
            }
            
            return try response.content.syncDecode(GoogleUserInfo.self)
        }
    }
}
