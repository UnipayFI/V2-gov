// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {BaseHook, Hooks} from "./utils/BaseHook.sol";
import {BaseInitiative} from "./BaseInitiative.sol";

contract UniV4Donations is BaseInitiative, BaseHook {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    uint256 public immutable VESTING_EPOCH_START;
    uint256 public immutable VESTING_EPOCH_DURATION;

    address private immutable currency0;
    address private immutable currency1;
    uint24 private immutable fee;
    int24 private immutable tickSpacing;

    struct Vesting {
        uint240 amount;
        uint16 epoch;
        uint256 released;
    }

    Vesting public vesting;

    constructor(
        address _governance,
        address _bold,
        address _bribeToken,
        uint256 _vestingEpochStart,
        uint256 _vestingEpochDuration,
        address _poolManager,
        address _token,
        uint24 _fee,
        int24 _tickSpacing
    ) BaseInitiative(_governance, _bold, _bribeToken) BaseHook(IPoolManager(_poolManager)) {
        VESTING_EPOCH_START = _vestingEpochStart;
        VESTING_EPOCH_DURATION = _vestingEpochDuration;

        if (uint256(uint160(address(_bold))) <= uint256(uint160(address(_token)))) {
            currency0 = _bold;
            currency1 = _token;
        } else {
            currency1 = _token;
            currency0 = _bold;
        }
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    function vestingEpoch() public view returns (uint16) {
        return uint16(((block.timestamp - VESTING_EPOCH_START) / VESTING_EPOCH_DURATION)) + 1;
    }

    function vestingEpochStart() public view returns (uint256) {
        return VESTING_EPOCH_START + ((vestingEpoch() - 1) * VESTING_EPOCH_DURATION);
    }

    function restartVesting() public returns (Vesting memory) {
        uint16 epoch = vestingEpoch();
        Vesting memory _vesting = vesting;
        if (_vesting.epoch < epoch) {
            _vesting.amount = uint240(bold.balanceOf(address(this)));
            _vesting.epoch = epoch;
            _vesting.released = 0;
            vesting = _vesting;
        }
        return _vesting;
    }

    function _donateToPool() internal returns (uint256) {
        governance.claimForInitiative(address(this));
        Vesting memory _vesting = restartVesting();
        uint256 amount =
            (_vesting.amount * (block.timestamp - vestingEpochStart()) / VESTING_EPOCH_DURATION) - _vesting.released;
        if (amount != 0) {
            manager.donate(poolKey(), amount, 0, bytes(""));
            PoolKey memory key = poolKey();
            manager.sync(key.currency0);
            IERC20(Currency.unwrap(key.currency0)).transfer(address(manager), amount);
            manager.settle(key.currency0);
            vesting.released += amount;
        }
        return amount;
    }

    function donateToPool() public returns (uint256) {
        return abi.decode(manager.unlock(abi.encode(address(this), poolKey())), (uint256));
    }

    function poolKey() public view returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(this))
        });
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
        external
        override
        onlyByManager
        returns (bytes4)
    {
        require(PoolId.unwrap(poolKey().toId()) == PoolId.unwrap(key.toId()), "UniV4Donations: invalid-pool-id");
        return this.afterInitialize.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyByManager returns (bytes4, BalanceDelta) {
        require(PoolId.unwrap(poolKey().toId()) == PoolId.unwrap(key.toId()), "UniV4Donations: invalid-pool-id");
        _donateToPool();
        return (this.afterAddLiquidity.selector, delta);
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (address sender, PoolKey memory key) = abi.decode(data, (address, PoolKey));
        require(sender == address(this), "UniV4Donations: invalid-sender");
        require(PoolId.unwrap(poolKey().toId()) == PoolId.unwrap(key.toId()), "UniV4Donations: invalid-pool-id");
        return abi.encode(_donateToPool());
    }
}
