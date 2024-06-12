// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title DoubleLinkedList
/// @notice Implements a double linked list where the head is defined as the null item's next pointer
/// and the tail is defined as the null item's prev pointer
library DoubleLinkedList {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Item {
        uint256 prev;
        uint256 next;
    }

    struct List {
        mapping(uint256 => Item) items;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error IdIsZero();
    error ItemNotInList();
    error ItemInList();

    /*//////////////////////////////////////////////////////////////
                              LINKED LIST
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the head item id of the list if the `id` is 0
    /// @param list Linked list which contains the item
    /// @return _ Id of the head item
    function getHead(List storage list) internal view returns (uint256) {
        return list.items[0].next;
    }

    /// @notice Returns the tail item id of the list
    /// @param list Linked list which contains the item
    /// @return _ Id of the tail item
    function getTail(List storage list) internal view returns (uint256) {
        return list.items[0].prev;
    }

    /// @notice Returns the item id which follows item `id`. Returns the head item id of the list if the `id` is 0.
    /// @param list Linked list which contains the items
    /// @param id Id of the current item
    /// @return _ Id of the current item's next item
    function getNext(List storage list, uint256 id) internal view returns (uint256) {
        return list.items[id].next;
    }

    /// @notice Returns the item id which precedes item `id`. Returns the tail item id of the list if the `id` is 0.
    /// @param list Linked list which contains the items
    /// @param id Id of the current item
    /// @return _ Id of the current item's previous item
    function getPrev(List storage list, uint256 id) internal view returns (uint256) {
        return list.items[id].prev;
    }

    /// @notice Returns whether the list contains item `id`
    /// @param list Linked list which should contain the item
    /// @param id Id of the item to check
    /// @return _ True if the list contains the item, false otherwise
    function contains(List storage list, uint256 id) internal view returns (bool) {
        if (id == 0) revert IdIsZero();
        return (list.items[id].prev != 0 || list.items[id].next != 0 || list.items[0].next == id);
    }

    /// @notice Removes item `id` from the list
    /// @dev This function should not be called with an `id` that is not in the list
    /// @param list Linked list which contains the item
    /// @param id Id of the item to remove
    function remove(List storage list, uint256 id) internal {
        Item memory item = list.items[id];
        if (!contains(list, id)) revert ItemNotInList();
        list.items[item.prev].next = item.next;
        list.items[item.next].prev = item.prev;
        delete list.items[id];
    }

    /// @notice Inserts an item with `id` in the list before item `next`
    /// - if `next` is 0, the item is inserted at the end (tail) of the list
    /// - if `next` is the head of the list, the item is inserted at the beginning (head) of the list
    /// @dev This function should not be called with an `id` that is already in the list.
    /// @param list Linked list which contains the next item and into which the new item will be inserted
    /// @param id Id of the item to insert
    /// @param next Id of the item which should follow item `id`
    function insert(List storage list, uint256 id, uint256 next) internal {
        if (contains(list, id)) revert ItemInList();
        if (next != 0 && !contains(list, next)) revert ItemNotInList();
        uint256 prev = list.items[next].prev;
        list.items[next].prev = id;
        if (next == 0 && list.items[next].next == 0) list.items[next].next = id;
        list.items[prev].next = id;
        list.items[id].prev = prev;
        list.items[id].next = next;
    }
}
