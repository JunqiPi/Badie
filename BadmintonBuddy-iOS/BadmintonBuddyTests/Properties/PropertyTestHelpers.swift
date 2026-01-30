// PropertyTestHelpers.swift
// BadmintonBuddy v2.0 Property-Based Testing Utilities
//
// This file contains common generators and helpers for property-based tests
// using SwiftCheck framework.
//
// Property-based testing configuration:
// - Framework: SwiftCheck
// - Minimum iterations: 100 per property test
// - Tag format: "Feature: badminton-buddy-v2-upgrade, Property {N}: {property_text}"

import Foundation
import SwiftCheck

// MARK: - Test Configuration

/// Configuration constants for property-based tests
enum PropertyTestConfig {
    /// Minimum number of iterations for each property test
    static let minimumIterations = 100
    
    /// Feature tag for test identification
    static let featureTag = "badminton-buddy-v2-upgrade"
}

// MARK: - Generator Helpers

/// Helper function to create a property test tag
/// - Parameters:
///   - propertyNumber: The property number from the design document
///   - description: Brief description of the property
/// - Returns: Formatted tag string
func propertyTag(_ propertyNumber: Int, _ description: String) -> String {
    return "Feature: \(PropertyTestConfig.featureTag), Property \(propertyNumber): \(description)"
}

// MARK: - Common Generators

/// Generator for valid skill levels (1-9)
let skillLevelGen: Gen<Int> = Gen<Int>.fromElements(in: 1...9)

/// Generator for self-assignable skill levels (1-7)
let selfAssignableSkillLevelGen: Gen<Int> = Gen<Int>.fromElements(in: 1...7)

/// Generator for verification-required skill levels (8-9)
let verificationRequiredSkillLevelGen: Gen<Int> = Gen<Int>.fromElements(in: 8...9)

/// Generator for character ratings (1-5)
let characterRatingGen: Gen<Int> = Gen<Int>.fromElements(in: 1...5)

/// Generator for valid latitude values (-90 to 90)
let latitudeGen: Gen<Double> = Gen<Double>.fromElements(in: -90.0...90.0)

/// Generator for valid longitude values (-180 to 180)
let longitudeGen: Gen<Double> = Gen<Double>.fromElements(in: -180.0...180.0)

/// Generator for message content lengths (0-2000 characters for testing limits)
let messageLengthGen: Gen<Int> = Gen<Int>.fromElements(in: 0...2000)

/// Generator for time durations in seconds (0 to 10 hours for testing limits)
let durationSecondsGen: Gen<TimeInterval> = Gen<Double>.fromElements(in: 0...36000)

/// Generator for room participant counts (0-6 for testing limits)
let participantCountGen: Gen<Int> = Gen<Int>.fromElements(in: 0...6)

/// Generator for evaluation counts (0-20 for testing new player badge)
let evaluationCountGen: Gen<Int> = Gen<Int>.fromElements(in: 0...20)

// MARK: - Room Code Character Set

/// Valid characters for room codes (excluding confusing characters: 0, O, 1, I, L)
let roomCodeCharacters = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

/// Generator for valid room code characters
let roomCodeCharGen: Gen<Character> = Gen<Character>.fromElements(of: Array(roomCodeCharacters))
