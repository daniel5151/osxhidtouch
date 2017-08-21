//
//  ThingStream.swift
//
//  Created by Daniel Prilik on 2017-08-19
//

import Foundation

/**
 Model a stream of Things.

 Once the max-size is reached, pushes result in the removal of the oldest
 element in the list (FIFO)
 */
public final class ThingStream<T> {
    // Internally represented as a linked list
    private class Node<T> {
        let val: T

        var next: Node<T>? = nil
        var prev: Node<T>? = nil

        init(value: T) {
            self.val = value
        }
    }

    private let maxSize: UInt
    
    /// Number of elements in the stream
    private(set) var size: UInt = 0

    private var first: Node<T>?
    private var last: Node<T>?

    
    /// Init new stream
    ///
    /// - Parameter maxSize: Max number of elements
    init(maxSize: UInt) {
        assert(maxSize > 0)
        self.maxSize = maxSize
    }

    
    /// Add Thing to stream
    ///
    /// - Parameter val: The Thing to add!
    func push(val: T) {
        let newNode = Node(value: val)

        if self.first == nil {
            assert(self.last == nil)

            self.first = newNode
            self.last = newNode

            size = 1

            return
        }

        // Otherwise, add a element to the front
        newNode.next = self.first
        self.first!.prev = newNode
        self.first = newNode
        size += 1

        // Remove an element from the back if we have exceeded the max size
        if self.size > self.maxSize {
            self.last!.prev!.next = nil
            self.last = self.last!.prev
            self.size -= 1
        }
    }
    
    /// Empty out the stream
    func clear() {
        // the magic of Garbage Collection :)
        self.first = nil
        self.last = nil
        self.size = 0
    }
}

// Make it printable
extension ThingStream : CustomStringConvertible {
    public var description: String {
        var s = "["
        var n = self.first
        while n != nil {
            s += "\(n!.val)"
            n = n!.next
            if n != nil { s += ", " }
        }
        return s + "]"
    }
}

// Make it confrom to the Sequence spec (for iteration and such)
extension ThingStream : Sequence {
    public struct ThingStreamIterator : IteratorProtocol {
        let linkedList: ThingStream<T>
        private var next_node: Node<T>?

        init(_ linkedList: ThingStream<T>) {
            self.linkedList = linkedList
            self.next_node = linkedList.first
        }

        public mutating func next() -> T? {
            guard let prev_node = next_node else { return nil }
            next_node = prev_node.next
            return prev_node.val
        }
    }

    public func makeIterator() -> ThingStreamIterator {
        return ThingStreamIterator(self)
    }
}
