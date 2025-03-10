/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Note that this file is imported into SyncTests, too.

import Foundation
import Shared
import XCTest

@testable import Client
@testable import Storage

let threeMonthsInMillis: UInt64 = 3 * 30 * 24 * 60 * 60 * 1000
let threeMonthsInMicros: UInt64 = UInt64(threeMonthsInMillis) * UInt64(1000)

// Start everything three months ago.
let baseInstantInMillis = Date.nowMilliseconds() - threeMonthsInMillis
let baseInstantInMicros = Date.nowMicroseconds() - threeMonthsInMicros

func advanceTimestamp(_ timestamp: Timestamp, by: Int) -> Timestamp {
    return timestamp + UInt64(by)
}

func advanceMicrosecondTimestamp(_ timestamp: MicrosecondTimestamp, by: Int) -> MicrosecondTimestamp
{
    return timestamp + UInt64(by)
}

func populateHistoryForFrecencyCalculations(
    _ history: SQLiteHistory, siteCount count: Int, visitPerSite: Int = 4
) {
    for i in 0...count {
        let site = Site(url: "http://s\(i)ite\(i).com/foo".asURL!, title: "A \(i)")
        site.guid = "abc\(i)def"

        for j in 0..<visitPerSite {
            let visitTime = advanceMicrosecondTimestamp(
                baseInstantInMicros, by: (1_000_000 * i) + (1000 * j))
            addVisitForSite(site, intoHistory: history, atTime: visitTime)
        }
    }
}

func addVisitForSite(_ site: Site, intoHistory history: SQLiteHistory, atTime: MicrosecondTimestamp)
{
    let visit = SiteVisit(site: site, date: atTime, type: VisitType.link)
    history.addLocalVisit(visit).succeeded()
}

extension BrowserDB {
    func assertQueryReturns(_ query: String, int: Int) {
        XCTAssertEqual(
            int, self.runQuery(query, args: nil, factory: IntFactory).value.successValue![0])
    }
}

extension BrowserDB {
    func getGUIDs(_ sql: String) -> [GUID] {
        func guidFactory(_ row: SDRow) -> GUID {
            return row[0] as! GUID
        }

        guard let cursor = self.runQuery(sql, args: nil, factory: guidFactory).value.successValue
        else {
            XCTFail("Unable to get cursor.")
            return []
        }
        return cursor.asArray()
    }

    func getPositionsForChildrenOfParent(_ parent: GUID, fromTable table: String) -> [GUID: Int] {
        let args: Args = [parent]
        let factory: (SDRow) -> (GUID, Int) = {
            return ($0["child"] as! GUID, $0["idx"] as! Int)
        }
        let cursor = self.runQuery(
            "SELECT child, idx FROM \(table) WHERE parent = ?", args: args, factory: factory
        ).value.successValue!
        return cursor.reduce(
            [:],
            { (dict, pair) in
                var dict = dict
                if let (k, v) = pair {
                    dict[k] = v
                }
                return dict
            })
    }
}

// see also `skipTest` in ClientTests, UITests, and XCUITests
func skipTest(issue: Int, _ message: String) throws {
    throw XCTSkip("#\(issue): \(message)")
}
