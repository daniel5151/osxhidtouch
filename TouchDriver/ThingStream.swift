//
//  ThingStream.swift
//
//  Created by Daniel Prilik on 2017-08-19
//

import Foundation

/**
 Model a stream of T.
 
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
    private(set) var size: UInt = 0
    
    private var first: Node<T>?
    private var last: Node<T>?
    
    init(maxSize: UInt) {
        assert(maxSize > 0)
        self.maxSize = maxSize
    }
    
    func push(val: T) {
        let newNode = Node(value: val)
        
        if self.first == nil {
            assert(self.last == nil)
            
            self.first = newNode
            self.last = newNode
            
            size = 1
            
            return
        }
        
        // Otherwise, add a element to the end
        newNode.prev = self.last
        self.last!.next = newNode
        self.last = newNode
        size += 1
        
        // Remove an element from the front if we have exceeded the max size
        if self.size > self.maxSize {
            self.first!.next!.prev = nil
            self.first = self.first!.next
            self.size -= 1
        }
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
