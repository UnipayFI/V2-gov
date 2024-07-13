// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
// import {console} from "forge-std/console.sol";

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {BribeInitiative} from "../src/BribeInitiative.sol";
import {Governance} from "../src/Governance.sol";
import {WAD, PermitParams} from "../src/utils/Types.sol";

interface ILQTY {
    function domainSeparator() external view returns (bytes32);
}

contract GovernanceTest is Test {
    IERC20 private constant lqty = IERC20(address(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D));
    IERC20 private constant lusd = IERC20(address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address private constant stakingV1 = address(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    address private constant user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC);
    address private constant lusdHolder = address(0xcA7f01403C4989d2b1A9335A2F09dD973709957c);

    uint256 private constant REGISTRATION_FEE = 1e18;
    uint256 private constant REGISTRATION_THRESHOLD_FACTOR = 0.01e18;
    uint256 private constant VOTING_THRESHOLD_FACTOR = 0.04e18;
    uint256 private constant MIN_CLAIM = 500e18;
    uint256 private constant MIN_ACCRUAL = 1000e18;
    uint256 private constant EPOCH_DURATION = 604800;
    uint256 private constant EPOCH_VOTING_CUTOFF = 518400;
    uint256 private constant ALLOCATION_DELAY = 1;

    Governance private governance;
    address[] private initialInitiatives;

    address private baseInitiative2;
    address private baseInitiative3;
    address private baseInitiative1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        baseInitiative1 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3)),
                address(lusd),
                address(lqty)
            )
        );

        baseInitiative2 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2)),
                address(lusd),
                address(lqty)
            )
        );

        baseInitiative3 = address(
            new BribeInitiative(
                address(vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1)),
                address(lusd),
                address(lqty)
            )
        );

        initialInitiatives.push(baseInitiative1);
        initialInitiatives.push(baseInitiative2);

        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF,
                allocationDelay: ALLOCATION_DELAY
            }),
            initialInitiatives
        );
    }

    function test_deployUserProxy() public {
        address userProxy = governance.deriveUserProxyAddress(user);

        vm.startPrank(user);
        assertEq(governance.deployUserProxy(), userProxy);
        vm.expectRevert();
        governance.deployUserProxy();
        vm.stopPrank();

        governance.deployUserProxy();
        assertEq(governance.deriveUserProxyAddress(user), userProxy);
    }

    function test_depositLQTY_withdrawShares() public {
        vm.startPrank(user);

        // check address
        address userProxy = governance.deriveUserProxyAddress(user);

        // deploy and deposit 1 LQTY
        lqty.approve(address(userProxy), 1e18);
        assertEq(governance.depositLQTY(1e18), 1e18);
        (uint240 shares,) = governance.sharesByUser(user);
        assertEq(shares, 1e18);

        // deposit 2 LQTY
        vm.warp(block.timestamp + 86400 * 30);
        lqty.approve(address(userProxy), 2e18);
        assertEq(governance.depositLQTY(2e18), 2e18 * WAD / governance.currentShareRate());
        (shares,) = governance.sharesByUser(user);
        assertEq(shares, 1e18 + 2e18 * WAD / governance.currentShareRate());

        // withdraw 0.5 half of shares
        vm.warp(block.timestamp + 86400 * 30);
        (shares,) = governance.sharesByUser(user);
        assertEq(governance.withdrawLQTY(shares / 2), 1.5e18);

        // withdraw remaining shares
        (shares,) = governance.sharesByUser(user);
        assertEq(governance.withdrawLQTY(shares), 1.5e18);

        vm.stopPrank();
    }

    function test_depositLQTYViaPermit() public {
        vm.startPrank(user);
        VmSafe.Wallet memory wallet = vm.createWallet(uint256(keccak256(bytes("1"))));
        lqty.transfer(wallet.addr, 1e18);
        vm.stopPrank();
        vm.startPrank(wallet.addr);

        // check address
        address userProxy = governance.deriveUserProxyAddress(wallet.addr);

        PermitParams memory permitParams = PermitParams({
            owner: wallet.addr,
            spender: address(userProxy),
            value: 1e18,
            deadline: block.timestamp + 86400,
            v: 0,
            r: "",
            s: ""
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wallet.privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ILQTY(address(lqty)).domainSeparator(),
                    keccak256(
                        abi.encode(
                            0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9,
                            permitParams.owner,
                            permitParams.spender,
                            permitParams.value,
                            0,
                            permitParams.deadline
                        )
                    )
                )
            )
        );

        permitParams.v = v;
        permitParams.r = r;
        permitParams.s = s;

        // deploy and deposit 1 LQTY
        assertEq(governance.depositLQTYViaPermit(1e18, permitParams), 1e18);
        (uint240 shares,) = governance.sharesByUser(wallet.addr);
        assertEq(shares, 1e18);
    }

    function test_currentShareRate() public payable {
        vm.warp(0);
        governance = new Governance(
            address(lqty),
            address(lusd),
            stakingV1,
            address(0),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: 0,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF,
                allocationDelay: ALLOCATION_DELAY
            }),
            initialInitiatives
        );
        assertEq(governance.currentShareRate(), 1e18);

        vm.warp(1);
        assertGt(governance.currentShareRate(), 1e18);

        vm.warp(365 days);
        assertEq(governance.currentShareRate(), 2 * WAD);

        vm.warp(730 days);
        assertEq(governance.currentShareRate(), 3 * WAD);

        vm.warp(1095 days);
        assertEq(governance.currentShareRate(), 4 * WAD);
    }

    function test_epoch() public {
        assertEq(governance.epoch(), 1);

        vm.warp(block.timestamp + 7 days - 1);
        assertEq(governance.epoch(), 1);

        vm.warp(block.timestamp + 1);
        assertEq(governance.epoch(), 2);

        vm.warp(block.timestamp + 3653 days - 7 days);
        assertEq(governance.epoch(), 522); // number of weeks + 1
    }

    function test_sharesToVotes() public {
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 0);

        vm.warp(block.timestamp + 365 days);
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 1e18);

        vm.warp(block.timestamp + 730 days);
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 3e18);

        vm.warp(block.timestamp + 1095 days);
        assertEq(governance.sharesToVotes(governance.currentShareRate(), 1e18), 6e18);
    }

    function test_calculateVotingThreshold() public {
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: MIN_CLAIM,
                minAccrual: MIN_ACCRUAL,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF,
                allocationDelay: ALLOCATION_DELAY
            }),
            initialInitiatives
        );

        // check that votingThreshold is is high enough such that MIN_CLAIM is met
        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1, governance.currentShareRate());
        vm.store(address(governance), bytes32(uint256(5)), bytes32(abi.encode(snapshot)));
        (uint240 votes,,) = governance.votesSnapshot();
        assertEq(votes, 1e18);

        uint256 boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(3)), bytes32(abi.encode(boldAccrued)));
        assertEq(governance.boldAccrued(), 1000e18);

        assertEq(governance.calculateVotingThreshold(), MIN_CLAIM / 1000);

        // check that votingThreshold is 4% of votes of previous epoch
        governance = new Governance(
            address(lqty),
            address(lusd),
            address(stakingV1),
            address(lusd),
            IGovernance.Configuration({
                registrationFee: REGISTRATION_FEE,
                regstrationThresholdFactor: REGISTRATION_THRESHOLD_FACTOR,
                votingThresholdFactor: VOTING_THRESHOLD_FACTOR,
                minClaim: 10e18,
                minAccrual: 10e18,
                epochStart: block.timestamp,
                epochDuration: EPOCH_DURATION,
                epochVotingCutoff: EPOCH_VOTING_CUTOFF,
                allocationDelay: ALLOCATION_DELAY
            }),
            initialInitiatives
        );

        snapshot = IGovernance.VoteSnapshot(10000e18, 1, governance.currentShareRate());
        vm.store(address(governance), bytes32(uint256(5)), bytes32(abi.encode(snapshot)));
        (votes,,) = governance.votesSnapshot();
        assertEq(votes, 10000e18);

        boldAccrued = 1000e18;
        vm.store(address(governance), bytes32(uint256(3)), bytes32(abi.encode(boldAccrued)));
        assertEq(governance.boldAccrued(), 1000e18);

        assertEq(governance.calculateVotingThreshold(), 10000e18 * 0.04);
    }

    function test_registerInitiative() public {
        IGovernance.VoteSnapshot memory snapshot = IGovernance.VoteSnapshot(1e18, 1, governance.currentShareRate());
        vm.store(address(governance), bytes32(uint256(5)), bytes32(abi.encode(snapshot)));
        (uint240 votes,,) = governance.votesSnapshot();
        assertEq(votes, 1e18);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        governance.registerInitiative(baseInitiative3);

        vm.startPrank(lusdHolder);
        lusd.transfer(address(this), 1e18);
        vm.stopPrank();

        lusd.approve(address(governance), 1e18);

        vm.expectRevert("Governance: insufficient-shares");
        governance.registerInitiative(baseInitiative3);

        vm.store(address(governance), keccak256(abi.encode(address(this), 1)), bytes32(abi.encode(1e18)));
        (uint240 shares,) = governance.sharesByUser(address(this));
        assertEq(shares, 1e18);
        vm.warp(block.timestamp + 365 days);

        governance.registerInitiative(baseInitiative3);
        assertEq(governance.initiativesRegistered(baseInitiative3), block.timestamp);
    }

    function test_allocateShares() public {
        vm.startPrank(user);

        // deploy
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1e18);
        assertEq(governance.depositLQTY(1e18), 1e18);

        assertEq(governance.qualifyingShares(), 0);
        (uint240 sharesAllocatedByUser_, uint16 atEpoch) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 0);
        assertEq(atEpoch, 0);

        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaShares = new int256[](1);
        deltaShares[0] = 1e18;
        int256[] memory deltaVetoShares = new int256[](1);

        vm.expectRevert("Governance: initiative-not-active");
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + 365 days);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        assertEq(governance.qualifyingShares(), 1e18);
        (sharesAllocatedByUser_, atEpoch) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 1e18);
        assertEq(atEpoch, governance.epoch());
        assertGt(atEpoch, 0);

        vm.expectRevert("Governance: insufficient-unallocated-shares");
        governance.withdrawLQTY(1e18);

        vm.warp(block.timestamp + governance.secondsUntilNextEpoch() - 1);

        initiatives[0] = baseInitiative1;
        deltaShares[0] = 1e18;
        vm.expectRevert("Governance: epoch-voting-cutoff");
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        initiatives[0] = baseInitiative1;
        deltaShares[0] = -1e18;
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        assertEq(governance.qualifyingShares(), 0);
        (sharesAllocatedByUser_,) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 0);

        vm.stopPrank();
    }

    function test_claimForInitiative() public {
        vm.startPrank(user);

        // deploy
        address userProxy = governance.deployUserProxy();

        lqty.approve(address(userProxy), 1000e18);
        assertEq(governance.depositLQTY(1000e18), 1000e18);

        vm.warp(block.timestamp + 365 days);

        assertEq(governance.qualifyingShares(), 0);
        (uint240 sharesAllocatedByUser_,) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 0);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        address[] memory initiatives = new address[](2);
        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        int256[] memory deltaShares = new int256[](2);
        deltaShares[0] = 500e18;
        deltaShares[1] = 500e18;
        int256[] memory deltaVetoShares = new int256[](2);
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);
        assertEq(governance.qualifyingShares(), 1000e18);
        (sharesAllocatedByUser_,) = governance.sharesAllocatedByUser(user);
        assertEq(sharesAllocatedByUser_, 1000e18);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(baseInitiative1), 5000e18);
        governance.claimForInitiative(baseInitiative1);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(lusd.balanceOf(baseInitiative1), 5000e18);

        assertEq(governance.claimForInitiative(baseInitiative2), 5000e18);
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();

        vm.startPrank(lusdHolder);
        lusd.transfer(address(governance), 10000e18);
        vm.stopPrank();

        vm.startPrank(user);

        initiatives[0] = baseInitiative1;
        initiatives[1] = baseInitiative2;
        deltaShares[0] = 495e18;
        deltaShares[1] = -495e18;
        governance.allocateShares(initiatives, deltaShares, deltaVetoShares);

        vm.warp(block.timestamp + governance.EPOCH_DURATION() + 1);

        assertEq(governance.claimForInitiative(baseInitiative1), 10000e18);
        assertEq(governance.claimForInitiative(baseInitiative1), 0);

        assertEq(lusd.balanceOf(baseInitiative1), 15000e18);

        assertEq(governance.claimForInitiative(baseInitiative2), 0);
        assertEq(governance.claimForInitiative(baseInitiative2), 0);

        assertEq(lusd.balanceOf(baseInitiative2), 5000e18);

        vm.stopPrank();
    }

    function test_multicall() public {
        vm.startPrank(user);

        vm.warp(block.timestamp + 365 days);

        uint256 lqtyAmount = 1000e18;
        uint256 shareAmount = lqtyAmount * WAD / governance.currentShareRate();
        uint256 lqtyBalance = lqty.balanceOf(user);

        lqty.approve(address(governance.deriveUserProxyAddress(user)), lqtyAmount);
        governance.deployUserProxy();
        governance.depositLQTY(lqtyAmount);

        vm.warp(block.timestamp + 365 days);

        bytes[] memory data = new bytes[](5);
        address[] memory initiatives = new address[](1);
        initiatives[0] = baseInitiative1;
        int256[] memory deltaShares = new int256[](1);
        deltaShares[0] = int256(shareAmount);
        int256[] memory deltaVetoShares = new int256[](1);

        int256[] memory deltaShares_ = new int256[](1);
        deltaShares_[0] = -int256(shareAmount);

        data[0] = abi.encodeWithSignature(
            "allocateShares(address[],int256[],int256[])", initiatives, deltaShares, deltaVetoShares
        );
        data[1] = abi.encodeWithSignature("sharesAllocatedToInitiative(address)", baseInitiative1);
        data[2] = abi.encodeWithSignature("snapshotVotesForInitiative(address)", baseInitiative1);
        data[3] = abi.encodeWithSignature(
            "allocateShares(address[],int256[],int256[])", initiatives, deltaShares_, deltaVetoShares
        );
        data[4] = abi.encodeWithSignature("withdrawLQTY(uint240)", uint240(shareAmount));
        bytes[] memory response = governance.multicall(data);

        (IGovernance.ShareAllocation memory shareAllocation) = abi.decode(response[1], (IGovernance.ShareAllocation));
        assertEq(shareAllocation.shares, shareAmount);
        (IGovernance.VoteSnapshot memory votes, IGovernance.InitiativeVoteSnapshot memory votesForInitiative) =
            abi.decode(response[2], (IGovernance.VoteSnapshot, IGovernance.InitiativeVoteSnapshot));
        assertEq(votes.votes + votesForInitiative.votes, 0);
        assertEq(lqty.balanceOf(user), lqtyBalance);

        vm.stopPrank();
    }
}
