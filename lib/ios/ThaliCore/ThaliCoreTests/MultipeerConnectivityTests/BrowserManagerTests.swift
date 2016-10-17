//
//  Thali CordovaPlugin
//  BrowserManagerTests.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

@testable import ThaliCore
import XCTest

class BrowserManagerTests: XCTestCase {

    // MARK: - State
    var advertiserManager: AdvertiserManager!
    var serviceType: String!

    let streamReceivedTimeout: NSTimeInterval = 5.0
    let peerAvailabilityHandlerTimeout: NSTimeInterval = 5.0
    let disposeTimeout: NSTimeInterval = 2.0
    let getErrorOnStartListeningTimeout: NSTimeInterval = 5.0
    let creatingMPCFSessionTimeout: NSTimeInterval = 5.0
    let connectTimeout: NSTimeInterval = 10.0

    override func setUp() {
        serviceType = String.randomValidServiceType(length: 7)
        advertiserManager = AdvertiserManager(serviceType: serviceType,
                                              disposeAdvertiserTimeout: disposeTimeout)
    }

    override func tearDown() {
        advertiserManager.stopAdvertising()
        advertiserManager = nil
    }

    // MARK: - Tests
    func testStartListeningChangesListeningState() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }

        // When
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)

        // Then
        XCTAssertTrue(browserManager.listening)

        browserManager.stopListeningForAdvertisements()
    }

    func testStopListeningChangesListeningState() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        XCTAssertTrue(browserManager.listening)

        // When
        browserManager.stopListeningForAdvertisements()

        // Then
        XCTAssertFalse(browserManager.listening)
    }

    func testStartStopStartListeningChangesListeningState() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }

        // When
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        // Then
        XCTAssertTrue(browserManager.listening)

        // When
        browserManager.stopListeningForAdvertisements()
        // Then
        XCTAssertFalse(browserManager.listening)

        // When
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        // Then
        XCTAssertTrue(browserManager.listening)

        browserManager.stopListeningForAdvertisements()
    }

    func testStartListeningCalledTwiceChangesStateProperly() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }

        // When
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        // Then
        XCTAssertTrue(browserManager.listening)

        browserManager.stopListeningForAdvertisements()
    }

    func testStopListeningCalledTwiceChangesStateProperly() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }

        // When
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        // Then
        XCTAssertTrue(browserManager.listening)

        // When
        browserManager.stopListeningForAdvertisements()
        browserManager.stopListeningForAdvertisements()
        // Then
        XCTAssertFalse(browserManager.listening)
    }

    func testConnectToPeerWithoutListeningReturnStartListeningNotActiveError() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }

        let getStartListeningNotActiveError =
            expectationWithDescription("got startListening not active error")
        var connectionError: ThaliCoreError?

        XCTAssertFalse(browserManager.listening)

        // When
        browserManager.connectToPeer(Peer().uuid, syncValue: "0") {
            [weak getStartListeningNotActiveError] syncValue, error, port in
            if let error = error as? ThaliCoreError {
                connectionError = error
                getStartListeningNotActiveError?.fulfill()
            }
        }

        // Then
        waitForExpectationsWithTimeout(getErrorOnStartListeningTimeout, handler: nil)
        XCTAssertEqual(connectionError, .StartListeningNotActive)

        browserManager.stopListeningForAdvertisements()
    }

    func testConnectToWrongPeerReturnsIllegalPeerIDError() {
        // Given
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1) { peers in }
        let getIllegalPeerIDError = expectationWithDescription("get Illegal Peer")
        var connectionError: ThaliCoreError?

        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)

        // When
        let notDiscoveredPeer = Peer()
        browserManager.connectToPeer(notDiscoveredPeer.uuid, syncValue: "0") {
            [weak getIllegalPeerIDError] syncValue, error, port in
            if let error = error as? ThaliCoreError {
                connectionError = error
                getIllegalPeerIDError?.fulfill()
            }
        }

        // Then
        let getIllegalPeerTimeout: NSTimeInterval = 5
        waitForExpectationsWithTimeout(getIllegalPeerTimeout, handler: nil)
        XCTAssertEqual(connectionError, .IllegalPeerID)

        browserManager.stopListeningForAdvertisements()
    }

    func testPickLatestGenerationAdvertiserOnConnect() {
        // Given
        let port1: UInt16 = 42
        let port2: UInt16 = 43

        var foundedAdvertisersCount = 0
        let expectedAdvertisersCount = 2
        let foundTwoAdvertisers = expectationWithDescription("found two advertisers")

        // Starting 1st generation of advertiser
        advertiserManager.startUpdateAdvertisingAndListening(onPort: port1,
                                                             errorHandler: unexpectedErrorHandler)
        guard let firstGenerationAdvertiserIdentifier =
            advertiserManager.advertisers.value.last?.peer else {
                XCTFail("Advertiser manager must have at least one advertiser")
                return
        }


        // Starting 2nd generation of advertiser
        advertiserManager.startUpdateAdvertisingAndListening(onPort: port2,
                                                             errorHandler: unexpectedErrorHandler)
        guard let secondGenerationAdvertiserIdentifier =
            advertiserManager.advertisers.value.last?.peer else {
                XCTFail("Advertiser manager must have at least one advertiser")
                return
        }

        let browserManager = BrowserManager(
            serviceType: serviceType,
            inputStreamReceiveTimeout: 1,
            peersAvailabilityChangedHandler: {
                [weak foundTwoAdvertisers] peerAvailability in

                if let
                    availability = peerAvailability.first
                    where
                        availability.peerIdentifier == secondGenerationAdvertiserIdentifier.uuid {
                            foundedAdvertisersCount += 1
                            if foundedAdvertisersCount == expectedAdvertisersCount {
                                foundTwoAdvertisers?.fulfill()
                            }
                }
            })

        // When
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)

        // Then
        waitForExpectationsWithTimeout(disposeTimeout, handler: nil)
        let lastGenerationOfAdvertiserPeer =
            browserManager.lastGenerationPeer(for: firstGenerationAdvertiserIdentifier.uuid)

        XCTAssertEqual(lastGenerationOfAdvertiserPeer?.generation,
                       secondGenerationAdvertiserIdentifier.generation)

        browserManager.stopListeningForAdvertisements()
    }

    func testReceivedPeerAvailabilityEventAfterFoundAdvertiser() {
        // Given
        let foundPeer = expectationWithDescription("found peer advertiser's identifier")

        var advertiserPeerAvailability: PeerAvailability? = nil

        advertiserManager.startUpdateAdvertisingAndListening(onPort: 42,
                                                             errorHandler: unexpectedErrorHandler)
        // When
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: 1,
                                            peersAvailabilityChangedHandler: {
                                                [weak foundPeer] peerAvailability in
                                                advertiserPeerAvailability = peerAvailability.first
                                                foundPeer?.fulfill()
                                            })
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)

        // Then
        waitForExpectationsWithTimeout(disposeTimeout, handler: nil)

        if let advertiser = advertiserManager.advertisers.value.first {
            XCTAssertEqual(advertiserPeerAvailability?.available, true)
            XCTAssertEqual(advertiser.peer.uuid, advertiserPeerAvailability?.peerIdentifier)
        } else {
            XCTFail("AdvertiserManager does not have any advertisers")
        }

        browserManager.stopListeningForAdvertisements()
    }

    func testIncrementAvailablePeersWhenFoundPeer() {
        // Given
        let MPCFConnectionCreated =
            expectationWithDescription("MPCF connection is created")

        let (advertiserManager, browserManager) = createMPCFPeers {
            peerAvailability in
            MPCFConnectionCreated.fulfill()
        }

        // When
        waitForExpectationsWithTimeout(creatingMPCFSessionTimeout, handler: nil)

        // Then
        XCTAssertEqual(1,
                       browserManager.availablePeers.value.count,
                       "BrowserManager has not available peers")

        browserManager.stopListeningForAdvertisements()
        advertiserManager.stopAdvertising()
    }

    func testPeerAvailabilityChangedAfterStartAdvertising() {
        // Given
        let peerAvailabilityChangedToTrue =
            expectationWithDescription("PeerAvailability changed to true")

        var advertiserPeerAvailability: PeerAvailability? = nil

        let browserManager = BrowserManager(
            serviceType: serviceType,
            inputStreamReceiveTimeout: 1,
            peersAvailabilityChangedHandler: {
                [weak peerAvailabilityChangedToTrue] peerAvailability in

                if let peerAvailability = peerAvailability.first {
                    if peerAvailability.available {
                        // When
                        advertiserPeerAvailability = peerAvailability
                        peerAvailabilityChangedToTrue?.fulfill()
                    }
                }
            })

        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        advertiserManager.startUpdateAdvertisingAndListening(onPort: 42,
                                                             errorHandler: unexpectedErrorHandler)

        // Then
        waitForExpectationsWithTimeout(peerAvailabilityHandlerTimeout, handler: nil)
        XCTAssertEqual(advertiserManager.advertisers.value.first!.peer.uuid,
                       advertiserPeerAvailability?.peerIdentifier)

        browserManager.stopListeningForAdvertisements()
    }

    func testPeerAvailabilityChangedAfterStopAdvertising() {
        // Expectations
        let peerAvailabilityChangedToFalse =
            expectationWithDescription("PeerAvailability changed to false")

        // Given
        let browserManager = BrowserManager(
            serviceType: serviceType,
            inputStreamReceiveTimeout: 1,
            peersAvailabilityChangedHandler: {
                [weak advertiserManager, weak peerAvailabilityChangedToFalse]
                peerAvailability in

                if let peerAvailability = peerAvailability.first {
                    if peerAvailability.available {
                        // When
                        advertiserManager?.stopAdvertising()
                    } else {
                        peerAvailabilityChangedToFalse?.fulfill()
                    }
                }
            })

        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)
        advertiserManager.startUpdateAdvertisingAndListening(onPort: 42,
                                                             errorHandler: unexpectedErrorHandler)

        // Then
        waitForExpectationsWithTimeout(peerAvailabilityHandlerTimeout, handler: nil)

        browserManager.stopListeningForAdvertisements()
    }

    func testConnectToPeerMethodReturnsTCPPort() {
        // Expectations
        var MPCFBrowserFoundAdvertiser: XCTestExpectation?
        var TCPSocketSuccessfullyCreated: XCTestExpectation?

        // Given
        // Prepare pair of advertiser and browser
        MPCFBrowserFoundAdvertiser =
            expectationWithDescription("Browser peer found Advertiser peer")

        // Start listening for advertisements on browser
        let browserManager = BrowserManager(serviceType: serviceType,
                                            inputStreamReceiveTimeout: streamReceivedTimeout,
                                            peersAvailabilityChangedHandler: {
                                                peerAvailability in

                                                guard let peer = peerAvailability.first else {
                                                    XCTFail("Browser didn't find Advertiser peer")
                                                    return
                                                }
                                                XCTAssertTrue(peer.available)
                                                MPCFBrowserFoundAdvertiser?.fulfill()
                                            })
        browserManager.startListeningForAdvertisements(unexpectedErrorHandler)

        // Start advertising on advertiser
        let advertiserManager = AdvertiserManager(serviceType: serviceType,
                                                  disposeAdvertiserTimeout: disposeTimeout)
        advertiserManager.startUpdateAdvertisingAndListening(onPort: 0,
                                                             errorHandler: unexpectedErrorHandler)

        waitForExpectationsWithTimeout(connectTimeout) {
            error in
            MPCFBrowserFoundAdvertiser = nil
        }

        TCPSocketSuccessfullyCreated = expectationWithDescription("Browser has returned TCP socket")

        // When
        let peerToConnect = browserManager.availablePeers.value.first!
        browserManager.connectToPeer(peerToConnect.uuid, syncValue: "0") {
            syncValue, error, port in

            guard error == nil else {
                XCTFail("Error during connection: \(error.debugDescription)")
                return
            }

            TCPSocketSuccessfullyCreated?.fulfill()
        }

        // Then
        waitForExpectationsWithTimeout(connectTimeout) {
            error in
            guard error == nil else {
                XCTFail("Browser couldn't connect to peer")
                return
            }
            browserManager.stopListeningForAdvertisements()
            TCPSocketSuccessfullyCreated = nil
        }

        advertiserManager.stopAdvertising()
    }
}