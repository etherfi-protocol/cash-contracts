// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimeLib} from "../src/libraries/TimeLib.sol"; // Adjust the import path as needed

contract TimeLibTest is Test {
    using TimeLib for uint256;

    function test_GetStartOfNextDay() public pure {
        // Test case 1: A normal timestamp
        uint256 timestamp = 1729987200; // October 27, 2024, 00:00 UTC
        int256 timezoneOffset = 0;
        uint256 startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);
        assertEq(startOfNextDay, 1730073600, "Failed for 00:00 UTC"); // October 28, 2024, 00:00 UTC

        // Test case 2: Timestamp near the end of the day
        timestamp = 1730073599; // October 27, 2024, 23:59:59 UTC
        startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);
        assertEq(startOfNextDay, 1730073600, "Failed near end of day"); // October 28, 2024, 00:00 UTC

        // Test case 3: Timezone offset (+4 hour) -> Dubai Timezone
        timezoneOffset = 4 * 60 * 60; // +4 hour offset
        timestamp = 1729987200; // October 27, 2024, 00:00 UTC
        startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);
        assertEq(startOfNextDay, 1730059200, "Failed for +4 hour offset"); // October 28, 2024, 01:00 UTC

        // Test case 3: Timezone offset (-5 hour) -> Cayman time
        timezoneOffset = -5 * 60 * 60; // -5 hour offset
        timestamp = 1729987200; // October 27, 2024, 00:00 UTC
        startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);
        assertEq(startOfNextDay, 1730005200, "Failed for -5 hour offset"); // October 28, 2024, 01:00 UTC
    }

    function test_GetStartOfNextWeek() public pure {
        // Test case 1: A normal timestamp 
        uint256 timestamp = 1730160000; // October 29, 2024, 00:00 UTC (Tuesday)
        int256 timezoneOffset = 0;
        uint256 startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1730678400, "Failed for 0 offset"); // November 4, 2024, 00:00 UTC

        // Test case 2: Timestamp with offset (+4 hours) -> Dubai Timezone 
        timezoneOffset = 4 * 60 * 60; // +4 hour offset
        timestamp = 1730160000; // October 29, 2024, 00:00 UTC
        startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1730664000, "Failed for +4 hour offset"); // November 3, 2024, 20:00 UTC

        // Test case 3: Timestamp with offset (-5 hours) -> Cayman Timezone 
        timezoneOffset = -5 * 60 * 60; // +4 hour offset
        timestamp = 1730160000; // October 29, 2024, 00:00 UTC
        startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1730696400, "Failed for -5 hour offset"); // November 4, 2024, 05:00 UTC

        // Test case 4: Timestamp near the start of the week
        timezoneOffset = 0; // -2 hour offset
        timestamp = 1730073600; // October 28, 2024, 00:00 UTC (Monday)
        startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1730678400, "Failed near the start of the week"); // November 3, 2024, 22:00 UTC

        // Test case 5: Timestamp near the end of the week
        timestamp = 1730678399; // November 3, 2024, 23:59:59 UTC
        startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1730678400, "Failed near the end of the week"); // November 4, 2024, 00:00 UTC
    }

    function test_GetStartOfNextMonth() public pure {
        // Test case 1: Normal month (October)
        uint256 timestamp = 1729987200; // October 27, 2024, 00:00 UTC
        int256 timezoneOffset = 0;
        uint256 startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1730419200, "Failed for October"); // November 1, 2024, 00:00 UTC

        // Test case 2: Timezone offset (+4 hours) -> Dubai Timezone
        timezoneOffset = 4 * 60 * 60; // +4 hours offset
        timestamp = 1729987200; // October 27, 2024, 00:00 UTC
        startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1730404800, "Failed for +4 timezone"); // October 31, 2024, 20:00 UTC

        // Test case 3: Timezone offset (-5 hours) -> Cayman Timezone
        timezoneOffset = -5 * 60 * 60; // -5 hours offset
        timestamp = 1729987200; // October 27, 2024, 00:00 UTC
        startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1730437200, "Failed for -5 timezone"); // November 1, 2024, 05:00 UTC

        // Test case 4: Near the start of the month
        timezoneOffset = 0;
        timestamp = 1727740800; // October 1, 2024, 00:00 UTC
        startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1730419200, "Failed near the start of the month"); // November 1, 2024, 00:00 UTC

        // Test case 5: Near the end of the month
        timezoneOffset = 0; 
        timestamp = 1730419199; // October 31, 2024, 23:59:59 UTC
        startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1730419200, "Failed near the end of the month"); // November 1, 2024, 00:00 UTC
    }

    function test_GetStartOfNextDay_LeapYear() public pure {
        // Test case 1: February 28th in a leap year (2024)
        uint256 timestamp = 1709078400; // February 28, 2024, 00:00 UTC
        int256 timezoneOffset = 0;
        uint256 startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);
        assertEq(startOfNextDay, 1709164800, "Failed for leap year February 28th"); // February 29, 2024, 00:00 UTC

        // Test case 2: February 29th in a leap year (2024)
        timestamp = 1709164800; // February 29, 2024, 00:00 UTC
        startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);
        assertEq(startOfNextDay, 1709251200, "Failed for leap year February 29th"); // March 1, 2024, 00:00 UTC
    }

    function test_GetStartOfNextWeek_LeapYear() public pure {
        // Test case 1: February 26th in a leap year (2024)
        uint256 timestamp = 1708905600; // February 26, 2024, 00:00 UTC (Monday)
        int256 timezoneOffset = 0;
        uint256 startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1709510400, "Failed for leap year February 26th"); // March 4, 2024, 00:00 UTC

        // Test case 2: March 1st in a leap year (2024)
        timestamp = 1709251200; // March 1, 2024, 00:00 UTC
        startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        assertEq(startOfNextWeek, 1709510400, "Failed for leap year March 1st"); // March 4, 2024, 00:00 UTC
    }

    function test_GetStartOfNextMonth_LeapYear() public pure {
        // Test case 1: February in a leap year (2024)
        uint256 timestamp = 1709164800; // February 29, 2024, 00:00 UTC
        int256 timezoneOffset = 0;
        uint256 startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1709251200, "Failed for leap year February"); // March 1, 2024, 00:00 UTC

        // Test case 2: March in a leap year (2024)
        timestamp = 1709251200; // March 1, 2024, 00:00 UTC
        startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        assertEq(startOfNextMonth, 1711929600, "Failed for leap year March"); // April 1, 2024, 00:00 UTC
    }

    function test_FuzzGetStartOfNextDay(uint256 timestamp, int256 timezoneOffset) public pure {
        (timestamp, timezoneOffset) = normalize(timestamp, timezoneOffset);

        // Calculate the start of the next day with the given timestamp and timezone offset
        uint256 startOfNextDay = TimeLib.getStartOfNextDay(timestamp, timezoneOffset);

        // The start of the next day should always be after the current timestamp
        assertTrue(startOfNextDay > timestamp, "Next day start time should be after the current time");

        // Ensure the start of the next day is within 48 hours of the current time
        assertTrue(startOfNextDay <= timestamp + 2 * 1 days, "Next day start time is more than 48 hours away");
    }

    function test_FuzzGetStartOfNextWeek(uint256 timestamp, int256 timezoneOffset) public pure {
        (timestamp, timezoneOffset) = normalize(timestamp, timezoneOffset);

        uint256 startOfNextWeek = TimeLib.getStartOfNextWeek(timestamp, timezoneOffset);
        // The start of the next week should always be after the current timestamp
        assertTrue(startOfNextWeek > timestamp, "Next week start time should be after the current time");
        // The start of the next week should be within 8 days of the current timestamp
        assertTrue(startOfNextWeek <= timestamp + 8 * 1 days, "Next week start time is more than 8 days away");
    }

    function test_FuzzGetStartOfNextMonth(uint256 timestamp, int256 timezoneOffset) public pure {
        (timestamp, timezoneOffset) = normalize(timestamp, timezoneOffset);

        uint256 startOfNextMonth = TimeLib.getStartOfNextMonth(timestamp, timezoneOffset);
        // The start of the next month should always be after the current timestamp
        assertTrue(startOfNextMonth > timestamp, "Next month start time should be after the current time");
        // The start of the next month should be within 32 days of the current timestamp
        assertTrue(startOfNextMonth <= timestamp + 32 * 1 days, "Next month start time is more than 32 days away");
    }

    function normalize(uint256 timestamp, int256 timezoneOffset) internal pure returns (uint256, int256) {
        // Limit timestamp to a reasonable range (Unix time 0 to ~2^40)
        vm.assume(timestamp < 2 ** 40);
        // Normalize timezone offset to range (-12 hours to +12 hours)
        vm.assume(timezoneOffset > -12 * 60 * 60 && timezoneOffset < 12 * 60 * 60);
        // Prevent underflow for negative timezone offsets by adding this condition
        vm.assume(int256(timestamp) + timezoneOffset >= 0);

        return (timestamp, timezoneOffset);
    }
}
