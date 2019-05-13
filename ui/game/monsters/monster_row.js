// Inherit from this to manually manage child views for performance reasons
// For views that display rows of citizens.
// Reduces DOM and view reconstruction for views that often simply remove/add a row
App.TDMonsterRowContainerView = App.ContainerView.extend({
   tagName: 'tbody',
   templateName: null,
   containerParentView: null,
   currentMonstersMap: {},
   rowCtor: null,

   init: function() {
      this._super();
      var self = this;

      if (this.containerParentView) {
         this.containerParentView.setMonsterRowContainerView(this);
      }
   },

   // Override this with arguments to the view ctor
   constructRowViewArgs: function(monsterId, entry) {
      return {
         uri: entry.__self,
         monsterId: monsterId,
      };
   },

   getRowChanges: function(monstersMap) {
      var self = this;
      var rowsToAdd = [];
      var rowsToRemove = [];
      radiant.each(monstersMap, function(monsterId, monsterData) {
         if (!self.currentMonstersMap[monsterId]) {
            rowsToAdd.push(self.constructRowViewArgs(monsterId, monsterData));
         }
      });

      radiant.each(self.currentMonstersMap, function(monsterId, monsterData) {
         if (!monstersMap[monsterId]) {
            rowsToRemove.push(monsterId);
         }
      });

      return {
         rowsToAdd: rowsToAdd,
         rowsToRemove: rowsToRemove,
         numRowsChanged: rowsToAdd.length + rowsToRemove.length,
      }
   },

   updateRows: function(monstersMap) {
      var self = this;
      var rowChanges = self.getRowChanges(monstersMap);
      var rowsToAdd = rowChanges.rowsToAdd;
      var rowsToRemove = rowChanges.rowsToRemove;

      self.currentMonstersMap = monstersMap;

      // Add/remove rows as needed
      var numRowsChanged = rowChanges.numRowsChanged;
      if (numRowsChanged > 1) {
         self.processRowChanges(rowChanges);
      } else if (numRowsChanged == 1) {
         // Add or remove a single row
         if (rowsToAdd.length > 0) {
            self.insertInSortedOrder(rowsToAdd[0]);
         } else {
            self.removeRow(rowsToRemove[0]);
         }
      }
   },

   processRowChanges: function(rowChanges) {
      for (var i = 0; i < rowChanges.rowsToAdd.length; i++) {
         this.addRow(rowChanges.rowsToAdd[i]); 
      }
      for (var i = 0; i < rowChanges.rowsToRemove.length; i++) {
         this.removeRow(rowChanges.rowsToRemove[i]); 
      }

      this.resetChildren();
   },

   resetChildren: function() {
      this.setObjects(this.toArray());
   },

   insertInSortedOrder: function(rowToInsert) {
      // Insert row at the beginning by default
      this.addRow(rowToInsert, 0);
   },

   addRow: function(args, index) {
      // Add child view at specified index
      // Pass `true` so that this behaves like a child view that is 
      // typically created using a handlebars template (clicks are not swallowed)
      this.addView(this.rowCtor, args, true, index);
   },

   removeRow: function(monsterId) {
      var removeIndex = null;
      // Find the index for the row that matches this citizen
      this.forEach(function(item, index, enumerable) {
         if (item.monsterId == monsterId) {
            removeIndex = index;
         }
      });

      // Remove and destroy view
      if (removeIndex != null) {
         var rowView = this.objectAt(removeIndex);
         this.removeChild(rowView);
         rowView.destroy();
      }
   },
});
