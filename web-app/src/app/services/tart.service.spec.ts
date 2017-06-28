/* tslint:disable:no-unused-variable */

import { TestBed, async, inject } from '@angular/core/testing';
import { TartService } from './tart.service';

describe('TartServiceService', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [TartService]
    });
  });

  it('should ...', inject([TartService], (service: TartService) => {
    expect(service).toBeTruthy();
  }));
});
