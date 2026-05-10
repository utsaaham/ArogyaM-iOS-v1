enum Config {
    static let bearerToken = "afd5c76aa0d42dc163c4e7519bc2ae2282e1fde19cae4958392ba69bf4c86448"

    // Switch between local dev and production
    private static let baseURL = "http://192.168.1.194:30001"          // local
    // private static let baseURL = "https://your-app.vercel.app"  // vercel

    static let sendDataURL = "\(baseURL)/api/health/send-data"
    static let getDataURL  = "\(baseURL)/api/health/get-data"
}
