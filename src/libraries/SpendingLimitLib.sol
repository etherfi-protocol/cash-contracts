// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimeLib} from "./TimeLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

struct SpendingLimit {
    uint256 dailyLimit; // in USD with 6 decimals
    uint256 monthlyLimit; // in USD with 6 decimals
    uint256 spentToday; // in USD with 6 decimals
    uint256 spentThisMonth; // in USD with 6 decimals
    uint256 newDailyLimit; // in USD with 6 decimals
    uint256 newMonthlyLimit; // in USD with 6 decimals
    uint64 dailyRenewalTimestamp;
    uint64 monthlyRenewalTimestamp;
    uint64 dailyLimitChangeActivationTime;
    uint64 monthlyLimitChangeActivationTime;
    int256 timezoneOffset;
}

library SpendingLimitLib {
    using TimeLib for uint256;
    using Math for uint256;

    error ExceededDailySpendingLimit();
    error ExceededMonthlySpendingLimit();
    error DailyLimitCannotBeGreaterThanMonthlyLimit();
    error InvalidTimezoneOffset();

    function initialize(
        SpendingLimit storage limit,
        uint256 dailyLimit,
        uint256 monthlyLimit,
        int256 timezoneOffset
    ) internal sanity(dailyLimit, monthlyLimit) returns (SpendingLimit memory) {
        if (timezoneOffset > 24 * 60 * 60 || timezoneOffset < -24 * 60 * 60) revert InvalidTimezoneOffset();
        limit.dailyLimit = dailyLimit;
        limit.monthlyLimit = monthlyLimit;
        limit.timezoneOffset = timezoneOffset;
        limit.dailyRenewalTimestamp = block.timestamp.getStartOfNextDay(limit.timezoneOffset);
        limit.monthlyRenewalTimestamp = block.timestamp.getStartOfNextMonth(limit.timezoneOffset);

        return limit;
    }

    function currentLimit(SpendingLimit storage limit) internal {
        SpendingLimit memory finalLimit = getCurrentLimit(limit);
        
        limit.dailyLimit = finalLimit.dailyLimit;
        limit.monthlyLimit = finalLimit.monthlyLimit;
        limit.spentToday = finalLimit.spentToday;
        limit.spentThisMonth = finalLimit.spentThisMonth;
        limit.newDailyLimit = finalLimit.newDailyLimit;
        limit.newMonthlyLimit = finalLimit.newMonthlyLimit;
        limit.dailyRenewalTimestamp = finalLimit.dailyRenewalTimestamp;
        limit.monthlyRenewalTimestamp = finalLimit.monthlyRenewalTimestamp;
        limit.dailyLimitChangeActivationTime = finalLimit.dailyLimitChangeActivationTime;
        limit.monthlyLimitChangeActivationTime = finalLimit.monthlyLimitChangeActivationTime;
        // limit.timezoneOffset = finalLimit.timezoneOffset;
    }

    function spend(SpendingLimit storage limit, uint256 amount) internal {
        currentLimit(limit);

        if (limit.spentToday + amount > limit.dailyLimit) revert ExceededDailySpendingLimit();
        if (limit.spentThisMonth + amount > limit.monthlyLimit) revert ExceededMonthlySpendingLimit();

        limit.spentToday += amount;
        limit.spentThisMonth += amount;
    }

    function updateSpendingLimit(
        SpendingLimit storage limit,
        uint256 newDailyLimit,
        uint256 newMonthlyLimit,
        uint64 delay
    ) internal sanity(newDailyLimit, newMonthlyLimit) returns (SpendingLimit memory, SpendingLimit memory) {
        currentLimit(limit);
        SpendingLimit memory oldLimit = limit;

        if (newDailyLimit < limit.dailyLimit) {
            limit.newDailyLimit = newDailyLimit;
            limit.dailyLimitChangeActivationTime = uint64(block.timestamp) + delay;
        } else {
            limit.dailyLimit = newDailyLimit;
            limit.newDailyLimit = 0;
            limit.dailyLimitChangeActivationTime = 0;
        }
        
        if (newMonthlyLimit < limit.monthlyLimit) {
            limit.newMonthlyLimit = newMonthlyLimit;
            limit.monthlyLimitChangeActivationTime = uint64(block.timestamp) + delay;
        } else {
            limit.monthlyLimit = newMonthlyLimit;
            limit.newMonthlyLimit = 0;
            limit.monthlyLimitChangeActivationTime = 0;
        }

        return (oldLimit, limit);
    }

    function maxCanSpend(SpendingLimit memory limit) internal view returns (uint256) {
        limit = getCurrentLimit(limit);
        bool usingIncomingDailyLimit = false;
        bool usingIncomingMonthlyLimit = false;
        uint256 applicableDailyLimit = limit.dailyLimit;
        uint256 applicableMonthlyLimit = limit.monthlyLimit;
        
        if (limit.dailyLimitChangeActivationTime != 0) {
            applicableDailyLimit = limit.newDailyLimit;
            usingIncomingDailyLimit = true;
        }
        if (limit.monthlyLimitChangeActivationTime != 0) {
            applicableMonthlyLimit = limit.newMonthlyLimit;
            usingIncomingMonthlyLimit = true;
        }

        if (limit.spentToday > applicableDailyLimit) return 0;
        if (limit.spentThisMonth > applicableMonthlyLimit) return 0;
        
        return Math.max(applicableDailyLimit - limit.spentToday, applicableMonthlyLimit - limit.spentThisMonth);
    }

    function canSpend(SpendingLimit memory limit, uint256 amount) internal view returns (bool, string memory) {
        limit = getCurrentLimit(limit);

        bool usingIncomingDailyLimit = false;
        bool usingIncomingMonthlyLimit = false;
        uint256 applicableDailyLimit = limit.dailyLimit;
        uint256 applicableMonthlyLimit = limit.monthlyLimit;

        if (limit.dailyLimitChangeActivationTime != 0) {
            applicableDailyLimit = limit.newDailyLimit;
            usingIncomingDailyLimit = true;
        }
        if (limit.monthlyLimitChangeActivationTime != 0) {
            applicableMonthlyLimit = limit.newMonthlyLimit;
            usingIncomingMonthlyLimit = true;
        }

        if (limit.spentToday > applicableDailyLimit) {
            if (usingIncomingDailyLimit) return (false, "Incoming daily spending limit already exhausted"); 
            else return (false, "Daily spending limit already exhausted"); 
        }

        if (limit.spentThisMonth > applicableMonthlyLimit) {
            if (usingIncomingMonthlyLimit) return (false, "Incoming monthly spending limit already exhausted"); 
            else return (false, "Monthly spending limit already exhausted"); 
        }

        uint256 availableDaily = applicableDailyLimit - limit.spentToday;
        uint256 availableMonthly = applicableMonthlyLimit - limit.spentThisMonth;

        if (amount > availableDaily) {
            if (usingIncomingDailyLimit) return (false, "Incoming daily available spending limit less than amount requested");
            return (false, "Daily available spending limit less than amount requested");
        } 
        
        if (amount > availableMonthly) {
            if (usingIncomingMonthlyLimit) return (false, "Incoming monthly available spending limit less than amount requested"); 
            return (false, "Monthly available spending limit less than amount requested"); 
        } 

        return (true, "");
    }

    function getCurrentLimit(SpendingLimit memory limit) internal view returns (SpendingLimit memory) {
        if (
            limit.dailyLimitChangeActivationTime != 0 &&
            block.timestamp > limit.dailyLimitChangeActivationTime
        ) {
            limit.dailyLimit = limit.newDailyLimit;
            // limit.dailyRenewalTimestamp = uint256(limit.dailyLimitChangeActivationTime).getStartOfNextDay(limit.timezoneOffset);
            limit.newDailyLimit = 0;
            limit.dailyLimitChangeActivationTime = 0;
        }

        if (limit.monthlyLimitChangeActivationTime != 0 && 
            block.timestamp > limit.monthlyLimitChangeActivationTime
        ) {
            limit.monthlyLimit = limit.newMonthlyLimit;
            // limit.monthlyRenewalTimestamp = uint256(limit.monthlyLimitChangeActivationTime).getStartOfNextMonth(limit.timezoneOffset);
            limit.newMonthlyLimit = 0;
            limit.monthlyLimitChangeActivationTime = 0;
        }

        if (block.timestamp > limit.dailyRenewalTimestamp) {
            limit.spentToday = 0;
            limit.dailyRenewalTimestamp = getFinalDailyRenewalTimestamp(limit.dailyRenewalTimestamp, limit.timezoneOffset);
        }

        if (block.timestamp > limit.monthlyRenewalTimestamp) {
            limit.spentThisMonth = 0;
            limit.monthlyRenewalTimestamp = getFinalMonthlyRenewalTimestamp(limit.monthlyRenewalTimestamp, limit.timezoneOffset);
        }

        return limit;
    }

    function getFinalDailyRenewalTimestamp(uint64 renewalTimestamp, int256 timezoneOffset) internal view returns (uint64) {
        do renewalTimestamp = uint256(renewalTimestamp).getStartOfNextDay(timezoneOffset);
        while (block.timestamp > renewalTimestamp);

        return renewalTimestamp;
    }

    function getFinalMonthlyRenewalTimestamp(uint64 renewalTimestamp, int256 timezoneOffset) internal view returns (uint64) {
        do renewalTimestamp = uint256(renewalTimestamp).getStartOfNextMonth(timezoneOffset);
        while (block.timestamp > renewalTimestamp);

        return renewalTimestamp;
    }

    modifier sanity(uint256 dailyLimit, uint256 monthlyLimit) {
        if (dailyLimit > monthlyLimit) revert DailyLimitCannotBeGreaterThanMonthlyLimit();
        _;
    }
}