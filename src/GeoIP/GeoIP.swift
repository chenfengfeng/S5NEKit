import Foundation
import MMDB

open class GeoIP {
    public static var database: MMDB!

    public static func LookUp(_ ipAddress: String) -> MMDBCountry? {
        return GeoIP.database.lookup(ipAddress)
    }
}
