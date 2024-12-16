// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TimeLib {
    // Function to find the timestamp for the start of the next day (00:00 in the user's time zone)
    function getStartOfNextDay(uint256 timestamp, int256 timezoneOffset) internal pure returns (uint64) {
        // Adjust the timestamp for the time zone offset
        int256 adjustedTimestamp = int256(timestamp) + timezoneOffset;

        // Calculate the current day in the adjusted time zone
        uint256 currentDay = uint256(adjustedTimestamp / 1 days);

        // Calculate the start of the next day in the adjusted time zone
        uint256 startOfNextDay = (currentDay + 1) * 1 days;

        // Adjust the result back to the user's local time zone
        return uint64(uint256(int256(startOfNextDay) - timezoneOffset));
    }
    
    // Function to find the start of the next week (Monday 00:00 in the user's time zone)
    function getStartOfNextWeek(uint256 timestamp, int256 timezoneOffset) internal pure returns (uint64) {
        // Adjust the timestamp for the time zone offset
        int256 adjustedTimestamp = int256(timestamp) + timezoneOffset;

        // Calculate the current day of the week (0 = Monday, 6 = Sunday)
        uint256 dayOfWeek = (uint256(adjustedTimestamp) / 1 days + 3) % 7;

        // Calculate the number of days until the next Monday
        uint256 daysUntilNextMonday = (dayOfWeek == 0) ? 7 : (7 - dayOfWeek);

        // Calculate the start of the next week in the adjusted time zone
        uint256 startOfNextWeek = ((uint256(adjustedTimestamp) / 1 days) + daysUntilNextMonday) * 1 days;

        // Adjust the result back to the user's local time zone
        return uint64(uint256(int256(startOfNextWeek) - timezoneOffset));
    }

    // Function to find the start of the next month (in the user's time zone)
    function getStartOfNextMonth(uint256 timestamp, int256 timezoneOffset) internal pure returns (uint64) {
        // Adjust the timestamp for the time zone offset
        int256 adjustedTimestamp = int256(timestamp) + timezoneOffset;

        // Get the current date in the adjusted time zone
        (uint16 year, uint8 month, ) = _daysToDate(uint256(adjustedTimestamp) / 1 days);

        // Increment the month and adjust the year if necessary
        month += 1;
        if (month > 12) {
            month = 1;
            year += 1;
        }

        // Calculate the start of the next month in the adjusted time zone
        uint256 startOfNextMonth = _daysFromDate(year, month, 1) * 1 days;

        // Adjust the result back to the user's local time zone
        return uint64(uint256(int256(startOfNextMonth) - timezoneOffset));
    }

    // Internal function to calculate days from date
    function _daysFromDate(uint16 year, uint8 month, uint8 day) internal pure returns (uint256) {
        int256 _year = int256(uint256(year));
        int256 _month = int256(uint256(month));
        int256 _day = int256(uint256(day));

        int256 __days = _day
            - 32075
            + 1461 * (_year + 4800 + (_month - 14) / 12) / 4
            + 367 * (_month - 2 - (_month - 14) / 12 * 12) / 12
            - 3 * ((_year + 4900 + (_month - 14) / 12) / 100) / 4
            - 2440588;

        return uint256(__days);
    }

    // Internal function to convert days to date
    function _daysToDate(uint256 _days) internal pure returns (uint16 year, uint8 month, uint8 day) {
        int256 __days = int256(_days);

        int256 L = __days + 68569 + 2440588;
        int256 N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int256 _month = 80 * L / 2447;
        int256 _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint16(uint256(_year));
        month = uint8(uint256(_month));
        day = uint8(uint256(_day));
    }
}