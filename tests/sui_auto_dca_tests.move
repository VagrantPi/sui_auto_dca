#[test_only]
module sui_auto_dca::sui_auto_dca_tests {

    // === Fee Calculation Tests ===

    #[test]
    fun test_fee_calculation_0_1_percent() {
        let dca_amount = 200_000_000u128;
        let total_fee_bps = 10u128;
        let keeper_share_rate = 3000u128;

        let total_fee = dca_amount * total_fee_bps / 10000;
        let keeper_share = total_fee * keeper_share_rate / 10000;
        let protocol_share = total_fee - keeper_share;

        assert!(total_fee == 200_000, 0);
        assert!(keeper_share == 60_000, 0);
        assert!(protocol_share == 140_000, 0);
    }

    #[test]
    fun test_fee_calculation_1_percent() {
        let dca_amount = 500_000_000u128;
        let total_fee_bps = 100u128;
        let keeper_share_rate = 5000u128;

        let total_fee = dca_amount * total_fee_bps / 10000;
        let keeper_share = total_fee * keeper_share_rate / 10000;
        let protocol_share = total_fee - keeper_share;

        assert!(total_fee == 5_000_000, 0);
        assert!(keeper_share == 2_500_000, 0);
        assert!(protocol_share == 2_500_000, 0);
    }

    #[test]
    fun test_fee_calculation_zero_fee() {
        let dca_amount = 100_000_000u128;
        let total_fee_bps = 0u128;

        let total_fee = dca_amount * total_fee_bps / 10000;
        assert!(total_fee == 0, 0);
    }

    #[test]
    fun test_fee_calculation_100_percent_fee() {
        let dca_amount = 100_000_000u128;
        let total_fee_bps = 10000u128;

        let total_fee = dca_amount * total_fee_bps / 10000;
        assert!(total_fee == dca_amount, 0);
    }

    #[test]
    fun test_keeper_share_calculation_100_percent() {
        let total_fee = 100_000u128;
        let keeper_share_rate = 10000u128;

        let keeper_share = total_fee * keeper_share_rate / 10000;
        assert!(keeper_share == total_fee, 0);
    }

    #[test]
    fun test_keeper_share_calculation_0_percent() {
        let total_fee = 100_000u128;
        let keeper_share_rate = 0u128;

        let keeper_share = total_fee * keeper_share_rate / 10000;
        assert!(keeper_share == 0, 0);
    }
}
