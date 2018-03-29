/*
 *  QuadTree.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 3/26/18.
 *  Copyright 2012-2018 Saildrone Inc
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "WhirlyVector.h"
#import <set>

namespace WhirlyKit
{

/** New implementation of the spatial quad tree.
    Used to identify tiles to load and unload.
    This version keeps very little state.
  */
class QuadTreeNew
{
public:
    QuadTreeNew(const MbrD &mbr,int minLevel,int maxLevel);
    virtual ~QuadTreeNew();
    
    // Single node in the Quad Tree
    class Node
    {
    public:
        Node() { }
        /// Construct with the cell coordinates and level.
        Node(int x,int y,int level) : x(x), y(y), level(level) { }
        
        /// Comparison based on x,y,level.  Used for sorting
        bool operator < (const Node &that) const;
        
        /// Quality operator
        bool operator == (const Node &that) const;
        
        /// Spatial subdivision along the X axis relative to the space
        int x;
        /// Spatial subdivision along tye Y axis relative to the space
        int y;
        /// Level of detail, starting with 0 at the top (low)
        int level;
    };
    typedef std::set<Node> NodeSet;

    // Node with an importance
    class ImportantNode : public Node
    {
    public:
        ImportantNode() { }
        ImportantNode(int x,int y,int level) : Node(x,y,level) { }

        bool operator < (const ImportantNode &that) const;
        bool operator == (const ImportantNode &that) const;
        
        double importance;
    };
    typedef std::set<ImportantNode> ImportantNodeSet;

    // Calculate a set of nodes to load based on importance, but only up to the maximum
    NodeSet calcCoverage(double minImportance,int maxNodes);
    
    // Generate a bounding box 
    MbrD generateMbrForNode(const Node &node);
    
    // Calculate a set of nodes to load based on the input level.
    // If it exceeds max nodes, we'll back off a level until we run out
//    NodeSet calcCoverageToLevel(int loadLevel,int maxNodes);

protected:
    // Filled in by the subclass
    virtual double importance(const Node &node) = 0;
    
    // Recursively visit the quad tree evaluating as we go
    void evalNode(ImportantNode node,double minImport,ImportantNodeSet &importSet);
    
    /// Bounding box
    MbrD mbr;
    
    /// Min/max zoom levels
    int minLevel,maxLevel;
};

}
