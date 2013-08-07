(function(calcentral) {
  'use strict';

  /**
   * Gritter controller
   */
  calcentral.controller('GritterController', ['$scope', 'apiService', function($scope, apiService) {

    $scope.$on('calcentral.api.refresh.inProgress', function(event, args) {
      $scope.inProgress = args;
    });
  }]);

})(window.calcentral);
