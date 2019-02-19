import Vapor
import Fluent
import Authentication

struct AcronymsController: RouteCollection {
    func boot(router: Router) throws {
        
        let acronymRoutes = router.grouped("api", "acronyms")
        
        acronymRoutes.get(use: getAllHandler)
        //acronymRoutes.post(Acronym.self, use: createHandler)
        acronymRoutes.get(Acronym.parameter, use: getHandler)
//        acronymRoutes.put(Acronym.parameter, use: updateHandler)
//        acronymRoutes.delete(Acronym.parameter, use: deleteHandler)
        acronymRoutes.get("search", use: searchHandler)
        acronymRoutes.get("first", use: getFirstHandler)
        acronymRoutes.get("sorted", use: sortedHandler)
        acronymRoutes.get(Acronym.parameter, "user", use:getUserHandler)
//        acronymRoutes.post(Acronym.parameter, "categories", Category.parameter, use: addCategoriesHandler)
        acronymRoutes.get(Acronym.parameter, "categories", use: getCategoriesHandler)
//        acronymRoutes.delete(Acronym.parameter, "categories", Category.parameter, use: removeCategoriesHandler)
        
        
        
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        let guardAuthMiddleware = User.guardAuthMiddleware()
        
        let tokenAuthGroup = acronymRoutes.grouped(tokenAuthMiddleware, guardAuthMiddleware)
        tokenAuthGroup.post(AcronymCreateData.self, use: createHandler)
        tokenAuthGroup.delete(Acronym.parameter, use: deleteHandler)
        tokenAuthGroup.put(Acronym.parameter, use: updateHandler)
        tokenAuthGroup.post(Acronym.parameter, "categories", Category.parameter, use: addCategoriesHandler)
        tokenAuthGroup.delete(Acronym.parameter, "categories", Category.parameter, use: removeCategoriesHandler)
        
//        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
//        let guardAuthMiddleware = User.guardAuthMiddleware()
//        let protected = acronymRoutes.grouped(basicAuthMiddleware, guardAuthMiddleware)
//        protected.post(Acronym.self, use: createHandler)
    }
    
    func getAllHandler(_ req:Request) throws -> Future<[Acronym]> {
        return Acronym.query(on: req).all()
    }
    
//    func createHandler(_ req: Request, acronym: Acronym) throws -> Future<Acronym> {
//        return acronym.save(on: req)
//    }
    
    func createHandler(_ req: Request, data: AcronymCreateData) throws -> Future<Acronym> {
        let user = try req.requireAuthenticated(User.self)
        let acronym = try Acronym(short: data.short, long: data.long, userID: user.requireID())
        return acronym.save(on: req)
    }
    
    func getHandler(_ req: Request) throws -> Future<Acronym> {
        return try req.parameters.next(Acronym.self)
    }
    
    func updateHandler(_ req:Request) throws -> Future<Acronym> {
        return try flatMap(to: Acronym.self,
                            req.parameters.next(Acronym.self),
                            req.content.decode(AcronymCreateData.self)) { acronym, updateData in
                                acronym.short = updateData.short
                                acronym.long = updateData.long
                                
                                let user = try req.requireAuthenticated(User.self)
                                acronym.userID = try user.requireID()
                                return acronym.save(on: req)
        }
    }
    
    func deleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        return try req.parameters.next(Acronym.self).delete(on: req).transform(to: HTTPStatus.noContent)
    }
    
    func searchHandler(_ req: Request) throws -> Future<[Acronym]> {
        guard let searchTerm = req.query[String.self, at: "term"] else {
            throw Abort(.badRequest)
        }
        
        return Acronym.query(on: req).group(.or) { or in
            or.filter(\.short == searchTerm)
            or.filter(\.long == searchTerm)
        }.all()
    }
    
    func getFirstHandler(_ req: Request) throws -> Future<Acronym> {
        return Acronym.query(on: req).first().map(to: Acronym.self) { acronym in
            guard let acronym = acronym else {
                throw Abort(.notFound)
            }
            return acronym
        }
    }
    
    func sortedHandler(_ req: Request) throws -> Future<[Acronym]> {
        return Acronym.query(on: req).sort(\.short, .ascending).all()
    }
    
    func getUserHandler(_ req: Request) throws -> Future<User.Public> {
        return try req.parameters.next(Acronym.self).flatMap(to: User.Public.self) { acronym in
            acronym.user.get(on: req).convertToPublic()
        }
    }
    
    func addCategoriesHandler(_ req: Request) throws -> Future<HTTPStatus> {
        return try flatMap(to: HTTPStatus.self,
                           req.parameters.next(Acronym.self),
                           req.parameters.next(Category.self)) { acronym, category in
                            return acronym.categories.attach(category, on: req).transform(to: .created)
        }
    }
    
    func getCategoriesHandler(_ req: Request) throws -> Future<[Category]> {
        return try req.parameters.next(Acronym.self).flatMap(to: [Category].self) { acronym in
            try acronym.categories.query(on: req).all()
        }
    }
    
    func removeCategoriesHandler(_ req: Request) throws -> Future<HTTPStatus> {
        return try flatMap(to: HTTPStatus.self,
                           req.parameters.next(Acronym.self),
                           req.parameters.next(Category.self)) { acronym, category in
                            return acronym.categories.detach(category, on: req).transform(to: .noContent)
            
        }
    }
}

struct AcronymCreateData: Content {
    let short: String
    let long: String
}
